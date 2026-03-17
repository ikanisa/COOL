import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
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
    area: "credit",
    prompt:
      "Generate a short, practical tip about building or improving one's credit score. Keep it relevant to emerging markets.",
    icon: "📈",
    cta_action: "/credit",
    cta_label: "Check Score",
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
    area: "mobility",
    prompt:
      "Generate a short, practical tip about ride-sharing, commuting smarter, or scheduling trips ahead of time. Relevant to African urban commuters.",
    icon: "🚗",
    cta_action: "/mobility/schedule",
    cta_label: "Schedule Ride",
  },
  {
    area: "rayon_sport",
    prompt:
      "Generate a short, engaging message about being an active football fan — attending matches, predicting scores, or engaging with a fan community. Reference Rayon Sport (Rwandan football club).",
    icon: "⚽",
    cta_action: "/rayon",
    cta_label: "Fan Zone",
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
  prompt: string
): Promise<GeneratedContent | null> {
  if (!GEMINI_API_KEY) {
    console.error("GEMINI_API_KEY not set");
    return null;
  }

  const systemPrompt = `You are a fintech app content generator for COOL, a mobile-first super-app in Rwanda/Malta. 
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
      }
    );

    if (!res.ok) {
      console.error("Gemini API error:", res.status, await res.text());
      return null;
    }

    const data = await res.json();
    const text =
      data?.candidates?.[0]?.content?.parts?.[0]?.text?.trim() ?? "";
    if (!text) return null;

    return JSON.parse(text) as GeneratedContent;
  } catch (e) {
    console.error("Gemini generation error:", e);
    return null;
  }
}

Deno.serve(async (req) => {
  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Check if generation is enabled
    const { data: config } = await supabase
      .from("ai_content_generation_config")
      .select("is_enabled")
      .limit(1)
      .single();

    // If called via cron (not manual), respect the is_enabled flag
    const url = new URL(req.url);
    const isManual = url.searchParams.get("manual") === "true";

    if (!isManual && !config?.is_enabled) {
      return new Response(
        JSON.stringify({
          success: false,
          reason: "Auto-generation is disabled by admin",
        }),
        { headers: { "Content-Type": "application/json" } }
      );
    }

    // Pick a random content template
    const template =
      CONTENT_TEMPLATES[Math.floor(Math.random() * CONTENT_TEMPLATES.length)];

    // Generate content via Gemini
    const generated = await generateWithGemini(template.prompt);

    if (!generated) {
      return new Response(
        JSON.stringify({ success: false, reason: "Generation failed" }),
        { headers: { "Content-Type": "application/json" } }
      );
    }

    // Check for duplicate titles
    const { data: existing } = await supabase
      .from("ai_content")
      .select("id")
      .eq("title", generated.title)
      .limit(1);

    if (existing && existing.length > 0) {
      // Append timestamp to make unique
      generated.title += ` (${new Date().toLocaleDateString()})`;
    }

    // Insert as pending_review — admin must approve
    const { error: insertError } = await supabase.from("ai_content").insert({
      title: generated.title,
      subtitle: generated.subtitle,
      body: generated.body,
      rationale: generated.rationale,
      content_type: "recommendation",
      status: "pending_review",
      icon_emoji: template.icon,
      cta_action: template.cta_action,
      cta_label: template.cta_label,
      sort_order: Math.floor(Math.random() * 100),
      is_active: false,
    });

    if (insertError) {
      console.error("Insert error:", insertError);
      return new Response(
        JSON.stringify({ success: false, error: insertError.message }),
        { headers: { "Content-Type": "application/json" } }
      );
    }

    // Update last_generated_at
    await supabase
      .from("ai_content_generation_config")
      .update({
        last_generated_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .not("id", "is", null); // update the singleton row

    return new Response(
      JSON.stringify({
        success: true,
        title: generated.title,
        area: template.area,
        status: "pending_review",
      }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (e) {
    console.error("Edge function error:", e);
    return new Response(
      JSON.stringify({ success: false, error: String(e) }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
