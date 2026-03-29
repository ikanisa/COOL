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
} from "../_shared/auth.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");

type MatchCommentaryRequest = {
  match_id?: string;
  home_team?: string;
  away_team?: string;
  home_score?: number;
  away_score?: number;
  competition?: string;
  venue?: string;
  commentary_type?: string;
};

type GeneratedCommentary = {
  title: string;
  body: string;
};

interface PromptParams {
  home_team: string;
  away_team: string;
  home_score?: number;
  away_score?: number;
  competition?: string;
  venue?: string;
  commentary_type: string;
}

type AdminClientLike = ReturnType<typeof createAdminClient>;

export type GenerateMatchCommentaryHandlerDependencies = {
  createAdminClient: () => AdminClientLike;
  requireAdminCaller: (request: Request) => Promise<AuthenticatedCaller>;
  generateCommentary: (params: PromptParams) => Promise<GeneratedCommentary>;
};

async function generateWithGemini(
  params: PromptParams,
): Promise<GeneratedCommentary> {
  if (!GEMINI_API_KEY) {
    throw new HttpError(500, "GEMINI_API_KEY is not configured.");
  }

  const prompt = buildPrompt(params);
  const geminiResponse = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${GEMINI_API_KEY}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: {
          temperature: 0.7,
          maxOutputTokens: 1024,
          responseMimeType: "application/json",
          responseSchema: {
            type: "object",
            properties: {
              title: { type: "string" },
              body: { type: "string" },
            },
            required: ["title", "body"],
          },
        },
      }),
    },
  );

  if (!geminiResponse.ok) {
    const errText = await geminiResponse.text();
    console.error("Gemini API error:", errText);
    throw new HttpError(502, "AI generation failed.");
  }

  const geminiData = await geminiResponse.json();
  const rawText = geminiData?.candidates?.[0]?.content?.parts?.[0]?.text ??
    "{}";

  try {
    return JSON.parse(rawText) as GeneratedCommentary;
  } catch {
    return {
      title: `${params.home_team} ${params.home_score ?? "?"} – ` +
        `${params.away_score ?? "?"} ${params.away_team}`,
      body: rawText,
    };
  }
}

const defaultDependencies: GenerateMatchCommentaryHandlerDependencies = {
  createAdminClient,
  requireAdminCaller,
  generateCommentary: generateWithGemini,
};

function normalizeCommentaryType(value: string | undefined) {
  const normalized = value?.trim().toLowerCase();
  return normalized === "preview" ? "preview" : "recap";
}

function parseRequestBody(body: MatchCommentaryRequest):
  & Required<
    Pick<MatchCommentaryRequest, "match_id" | "home_team" | "away_team">
  >
  & MatchCommentaryRequest {
  const matchId = body.match_id?.trim();
  const homeTeam = body.home_team?.trim();
  const awayTeam = body.away_team?.trim();

  if (!matchId || !homeTeam || !awayTeam) {
    throw new HttpError(
      400,
      "match_id, home_team, and away_team are required.",
    );
  }

  return {
    ...body,
    match_id: matchId,
    home_team: homeTeam,
    away_team: awayTeam,
  };
}

export function createGenerateMatchCommentaryHandler(
  dependencies: Partial<GenerateMatchCommentaryHandlerDependencies> = {},
) {
  const deps: GenerateMatchCommentaryHandlerDependencies = {
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
      const caller = await deps.requireAdminCaller(request);
      actorUserId = caller.userId;

      const body = parseRequestBody(
        await request.json() as MatchCommentaryRequest,
      );
      const commentaryType = normalizeCommentaryType(body.commentary_type);
      const generated = await deps.generateCommentary({
        home_team: body.home_team,
        away_team: body.away_team,
        home_score: body.home_score,
        away_score: body.away_score,
        competition: body.competition,
        venue: body.venue,
        commentary_type: commentaryType,
      });

      const { data, error } = await adminClient
        .from("rs_match_commentary")
        .insert({
          match_id: body.match_id,
          commentary_type: commentaryType,
          title: generated.title,
          body: generated.body,
          metadata: {
            model: "gemini-2.0-flash",
            generated_at: new Date().toISOString(),
            tone: "sports_journalist",
            generated_by: caller.userId,
            home_score: body.home_score,
            away_score: body.away_score,
          },
          is_published: true,
        })
        .select()
        .single();

      if (error) {
        console.error("Supabase insert error:", error);
        throw new HttpError(500, error.message);
      }

      return jsonResponse({ success: true, commentary: data });
    } catch (error) {
      if (error instanceof SyntaxError) {
        return errorResponse("Invalid JSON body.", 400);
      }
      if (error instanceof HttpError) {
        return errorResponse(error.message, error.status);
      }

      console.error("generate-match-commentary failed", error);
      await recordEdgeFunctionFailure(adminClient, {
        functionName: "generate-match-commentary",
        error,
        userId: actorUserId,
      });
      return errorResponse(
        error instanceof Error ? error.message : "Internal server error.",
        500,
      );
    }
  };
}

if (import.meta.main) {
  Deno.serve(createGenerateMatchCommentaryHandler());
}

function buildPrompt(params: PromptParams): string {
  const {
    home_team,
    away_team,
    home_score,
    away_score,
    competition,
    venue,
    commentary_type,
  } = params;

  if (commentary_type === "preview") {
    return `You are a professional sports journalist covering Rwandan football for Rayon Sports FC's official fan app.

Write a match preview for:
${home_team} vs ${away_team}
Competition: ${competition ?? "Rwanda Premier League"}
Venue: ${venue ?? "Kigali Pelé Stadium"}

Write in a formal, authoritative sports journalism style. Cover:
- Recent form and key storylines
- Tactical considerations
- Players to watch
- Your prediction for the match

Format as JSON with "title" (compelling headline) and "body" (2-3 paragraphs, ~150-200 words).`;
  }

  return `You are a professional sports journalist covering Rwandan football for Rayon Sports FC's official fan app.

Write a post-match recap for:
${home_team} ${home_score ?? "?"} – ${away_score ?? "?"} ${away_team}
Competition: ${competition ?? "Rwanda Premier League"}
Venue: ${venue ?? "Kigali Pelé Stadium"}

Write in a formal, authoritative sports journalism style. Cover:
- Match narrative and key moments
- Standout performances
- Tactical analysis
- What this result means for both teams

Format as JSON with "title" (compelling headline) and "body" (3-4 paragraphs, ~200-300 words).`;
}
