import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { createAdminClient, createUserClient } from "../_shared/supabase.ts";
import { 
  createGoogleDoc, 
  uploadToDrive, 
  sendGmail, 
  logAiAudit 
} from "../_shared/google_workspace.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
const GEMINI_MODEL = "gemini-2.0-pro-exp-02-05"; 
const GEMINI_URL =
  `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`;

function buildArchivePrompt(userData: any, stats: any) {
  return [
    "You are the 'COOL Wealth Concierge'.",
    "Analyze the user's performance for the last 30 days and write a professional yet encouraging Monthly Wealth Progress report.",
    "",
    "### USER DATA",
    `Name: ${userData.official_name || userData.full_name}`,
    `30-Day Activity: ${JSON.stringify(stats)}`,
    "",
    "### REPORT REQUIREMENTS",
    "1. HIGHLIGHTS: Mention their top spending categories and any positive savings group contributions.",
    "2. GOAL TRACKING: Comment on their progress toward financial health.",
    "3. CONCIERGE ADVICE: Suggest one specific area to optimize for next month.",
    "",
    "Use professional formatting suitable for a Google Doc.",
  ].join("\n");
}

Deno.serve(async (req: Request) => {
  const startTime = Date.now();
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method !== "POST") return methodNotAllowed();
  if (!GEMINI_API_KEY) return errorResponse("AI Service not configured.", 503);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return errorResponse("Missing authorization.", 401);

  const adminClient = createAdminClient();
  const userClient = createUserClient(authHeader);
  const { data: { user }, error: authError } = await userClient.auth.getUser();

  if (authError || !user) return errorResponse("Unauthorized.", 401);

  // 1. Aggregate Stats
  const { data: userData } = await adminClient.from("users").select("*").eq("id", user.id).single();
  const thirtyDaysAgo = new Date();
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

  const { data: txData } = await adminClient
    .from("momo_ledger_entries")
    .select("amount, entry_type, tx_category")
    .eq("user_id", user.id)
    .gte("tx_datetime", thirtyDaysAgo.toISOString());

  const txSummary = txData?.reduce((acc: any, tx: any) => {
    const cat = tx.tx_category || "other";
    if (!acc[cat]) acc[cat] = { total: 0, count: 0 };
    acc[cat].total += tx.amount;
    acc[cat].count += 1;
    return acc;
  }, {});

  // 2. AI Reasoning
  try {
    const prompt = buildArchivePrompt(userData, txSummary);
    const geminiResponse = await fetch(GEMINI_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.3 },
      }),
    });

    const result = await geminiResponse.json();
    const narrative = result.candidates[0].content.parts[0].text;

    // 3. Orchestrate Google Workspace (The "Concierge" Flow)
    const reportTitle = `COOL Monthly Progress - ${new Date().toLocaleString('default', { month: 'long', year: 'numeric' })}`;
    
    // a. Create Doc
    const docUrl = await createGoogleDoc(reportTitle, narrative);
    
    // b. Archive to Drive
    const driveUrl = await uploadToDrive(reportTitle, narrative);
    
    // c. Notify via Gmail
    const emailBody = `Hello ${userData.official_name || userData.full_name},\n\nYour COOL Wealth Archive for this month is ready.\n\nYou can view your report here: ${docUrl}\n\nA copy has been securely archived in your Google Drive: ${driveUrl}\n\nBest regards,\nYour COOL AI Concierge`;
    await sendGmail(userData.official_email || user.email!, reportTitle, emailBody);

    // 4. Governance Audit
    await logAiAudit({
      function_name: "run-monthly-archive",
      user_id: user.id,
      model: GEMINI_MODEL,
      confidence: 1.0,
      decision: "ARCHIVED",
      metadata: { doc_url: docUrl, drive_url: driveUrl },
      latency_ms: Date.now() - startTime
    });

    return jsonResponse({
      success: true,
      data: {
        doc_url: docUrl,
        drive_url: driveUrl,
        title: reportTitle
      }
    });

  } catch (err) {
    console.error("Archive Concierge Error:", err);
    return errorResponse("Failed to complete your wealth archive.", 500);
  }
});
