import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import {
  createAdminClient,
  createUserClient,
} from "../_shared/supabase.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";

interface ReconRow {
  id: string;
  match_status: string;
  parsed_sms_id: string;
  metadata: Record<string, unknown>;
}

interface ParsedSms {
  id: string;
  amount: number;
  payer_phone: string | null;
  payer_name: string | null;
  momo_tx_id: string | null;
  payee_phone: string | null;
}

interface GroupMember {
  user_id: string;
  display_name: string;
  phone: string;
  group_id: string;
  group_name: string;
  contribution_amount: number;
}

type AuthenticatedCaller = {
  userId: string;
  isAppAdmin: boolean;
  isGlobalBankAdmin: boolean;
  appMetadata: Record<string, unknown>;
};

class HttpError extends Error {
  constructor(public readonly status: number, message: string) {
    super(message);
  }
}

Deno.serve(async (req: Request) => {
  const corsResponse = handleCors(req);
  if (corsResponse) {
    return corsResponse;
  }

  if (req.method !== "POST") {
    return methodNotAllowed("POST");
  }

  try {
    const authorization =
      req.headers.get("authorization")?.trim() ??
      req.headers.get("Authorization")?.trim();
    if (!authorization) {
      return errorResponse("Authentication required", 401);
    }

    const caller = await requireCaller(authorization);
    const { partner_id } = await req.json().catch(() => ({ partner_id: null }));
    const partnerId = normalizePartnerId(partner_id);
    if (!partnerId) {
      return errorResponse("partner_id is required", 400);
    }
    if (!hasBankAdminAccess(caller, partnerId)) {
      return errorResponse(
        "Not authorized to allocate contributions for this partner.",
        403,
      );
    }

    const supabase = createAdminClient();

    // 1. Fetch unresolved reconciliations
    const { data: recons, error: reconErr } = await supabase
      .from("momo_reconciliations")
      .select("id, match_status, parsed_sms_id, metadata")
      .in("match_status", ["pending_review", "manual_review"])
      .order("created_at", { ascending: false })
      .limit(50);

    if (reconErr) {
      return jsonResponse({ error: reconErr.message }, 500);
    }

    if (!recons || recons.length === 0) {
      return jsonResponse({ message: "No unresolved allocations found.", processed: 0 });
    }

    // 2. Fetch parsed SMS data for these reconciliations
    const parsedIds = recons.map((r: ReconRow) => r.parsed_sms_id).filter(Boolean);
    const { data: parsedList } = await supabase
      .from("momo_sms_parsed")
      .select("id, amount, payer_phone, payer_name, momo_tx_id, payee_phone")
      .in("id", parsedIds);

    const parsedMap = new Map<string, ParsedSms>();
    for (const p of parsedList ?? []) {
      parsedMap.set(p.id, p);
    }

    // 3. Fetch all group members with user phones for matching
    const membersResult = await supabase.rpc("get_bank_all_group_members_for_matching", {
      p_partner_id: partnerId,
    });

    // Fallback: direct query if RPC doesn't exist
    let memberList: GroupMember[] = membersResult.error
      ? []
      : (membersResult.data ?? []);
    if (memberList.length === 0) {
      const { data: fallbackMembers } = await supabase
        .from("group_members")
        .select(`
          user_id,
          display_name,
          group_id,
          contribution_amount,
          users!inner(phone),
          groups!inner(name)
        `)
        .limit(500);

      memberList = (fallbackMembers ?? []).map((m: Record<string, unknown>) => ({
        user_id: m.user_id as string,
        display_name: (m.display_name as string) ?? "",
        phone: ((m as Record<string, Record<string, string>>).users?.phone) ?? "",
        group_id: m.group_id as string,
        group_name: ((m as Record<string, Record<string, string>>).groups?.name) ?? "",
        contribution_amount: (m.contribution_amount as number) ?? 0,
      }));
    }

    let processed = 0;
    let suggested = 0;
    let autoAllocated = 0;

    // 4. Process each unresolved reconciliation
    for (const recon of recons as ReconRow[]) {
      const parsed = parsedMap.get(recon.parsed_sms_id);
      if (!parsed) continue;

      const candidates = scoreCandidates(parsed, memberList, recon);

      if (candidates.length === 0) continue;

      const best = candidates[0];

      if (best.score >= 85) {
        // High confidence: auto-allocate
        try {
          await supabase.rpc("bank_allocate_manual_review_allocation", {
            p_partner_id: partnerId,
            p_review_id: recon.id,
            p_group_id: best.group_id,
            p_member_user_id: best.user_id,
            p_note: `AI auto-allocated (${best.score}% confidence). ${best.reasoning}`,
          });
          autoAllocated++;
        } catch {
          // If auto-allocate fails (e.g., auth issue), fall through to suggestion
          await writeSuggestion(supabase, recon.id, best);
          suggested++;
        }
      } else if (best.score >= 40) {
        // Medium confidence: suggest for review
        await writeSuggestion(supabase, recon.id, best);
        suggested++;
      }
      // Low confidence: leave as manual_review

      processed++;
    }

    // 5. If Gemini is available, do fuzzy name matching on remaining unresolved
    if (GEMINI_API_KEY) {
      const unresolved = recons.filter(
        (r: ReconRow) => !parsedMap.get(r.parsed_sms_id)
      );
      // Gemini enhancement would go here for truly ambiguous cases
      // For now, the scoring heuristic handles most cases well
    }

    return jsonResponse({
      message: "AI allocation complete.",
      processed,
      suggested,
      auto_allocated: autoAllocated,
      total_unresolved: recons.length,
    });
  } catch (err) {
    if (err instanceof HttpError) {
      return errorResponse(err.message, err.status);
    }
    return jsonResponse({ error: (err as Error).message }, 500);
  }
});

async function requireCaller(
  authorization: string,
): Promise<AuthenticatedCaller> {
  const userClient = createUserClient(authorization);
  const {
    data: { user },
    error,
  } = await userClient.auth.getUser();

  if (error || !user) {
    throw new HttpError(401, "Authentication required");
  }

  const appMetadata = (user.app_metadata ?? {}) as Record<string, unknown>;
  return {
    userId: user.id,
    isAppAdmin: metadataBool(appMetadata["is_admin"]),
    isGlobalBankAdmin: metadataBool(appMetadata["is_bank_admin"]),
    appMetadata,
  };
}

function normalizePartnerId(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function hasBankAdminAccess(
  caller: AuthenticatedCaller,
  partnerId: string,
): boolean {
  if (caller.isAppAdmin || caller.isGlobalBankAdmin) {
    return true;
  }

  const ids = caller.appMetadata["bank_admin_ids"];
  if (Array.isArray(ids)) {
    return ids.some((value) => value?.toString().trim() === partnerId);
  }
  if (ids && typeof ids === "object") {
    const entries = ids as Record<string, unknown>;
    return Object.entries(entries).some(
      ([key, value]) => key.trim() === partnerId && metadataBool(value),
    );
  }
  if (typeof ids === "string") {
    return ids.split(",").some((value) => value.trim() === partnerId);
  }
  return false;
}

function metadataBool(value: unknown): boolean {
  if (typeof value === "boolean") {
    return value;
  }
  if (typeof value === "number") {
    return value !== 0;
  }
  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase();
    return normalized === "true" || normalized === "1";
  }
  return false;
}

// ── Scoring engine ──────────────────────────────────────────────

interface ScoredCandidate {
  user_id: string;
  group_id: string;
  display_name: string;
  score: number;
  reasoning: string;
}

function scoreCandidates(
  parsed: ParsedSms,
  members: GroupMember[],
  recon: ReconRow,
): ScoredCandidate[] {
  const candidates: ScoredCandidate[] = [];
  const payerPhone = normalizePhone(parsed.payer_phone ?? "");
  const payerName = (parsed.payer_name ?? "").toLowerCase().trim();
  const amount = parsed.amount ?? 0;

  // Check metadata for group hints
  const metaGroupId = recon.metadata?.group_id as string | undefined;
  const matchingGroupIds = (recon.metadata?.matching_group_ids as string[]) ?? [];

  for (const member of members) {
    let score = 0;
    const reasons: string[] = [];
    const memberPhone = normalizePhone(member.phone);

    // Phone match (strongest signal)
    if (payerPhone && memberPhone && payerPhone === memberPhone) {
      score += 45;
      reasons.push("exact phone match");
    } else if (payerPhone && memberPhone && payerPhone.endsWith(memberPhone.slice(-6))) {
      score += 25;
      reasons.push("partial phone match (last 6 digits)");
    }

    // Name match
    if (payerName && member.display_name) {
      const memberName = member.display_name.toLowerCase().trim();
      if (payerName === memberName) {
        score += 30;
        reasons.push("exact name match");
      } else if (payerName.includes(memberName) || memberName.includes(payerName)) {
        score += 15;
        reasons.push("partial name match");
      } else {
        // Levenshtein-like similarity
        const sim = similarityScore(payerName, memberName);
        if (sim > 0.7) {
          score += Math.round(15 * sim);
          reasons.push(`fuzzy name match (${Math.round(sim * 100)}%)`);
        }
      }
    }

    // Amount match (expected contribution)
    if (amount > 0 && member.contribution_amount > 0) {
      if (amount === member.contribution_amount) {
        score += 15;
        reasons.push("exact amount match");
      } else if (Math.abs(amount - member.contribution_amount) / member.contribution_amount < 0.1) {
        score += 8;
        reasons.push("close amount match");
      }
    }

    // Group hint from metadata
    if (metaGroupId && member.group_id === metaGroupId) {
      score += 10;
      reasons.push("group hint from metadata");
    }
    if (matchingGroupIds.includes(member.group_id)) {
      score += 5;
      reasons.push("candidate group match");
    }

    if (score > 0) {
      candidates.push({
        user_id: member.user_id,
        group_id: member.group_id,
        display_name: member.display_name || member.phone,
        score: Math.min(score, 100),
        reasoning: reasons.join(", "),
      });
    }
  }

  // Sort by score descending
  candidates.sort((a, b) => b.score - a.score);
  return candidates.slice(0, 5); // Top 5
}

function normalizePhone(phone: string): string {
  const digits = phone.replace(/\D/g, "");
  if (digits.length === 10 && digits.startsWith("0")) {
    return "250" + digits.slice(1);
  }
  if (digits.length === 9) {
    return "250" + digits;
  }
  if (digits.startsWith("250") && digits.length === 12) {
    return digits;
  }
  return digits;
}

function similarityScore(a: string, b: string): number {
  if (a === b) return 1;
  const longer = a.length > b.length ? a : b;
  const shorter = a.length > b.length ? b : a;
  if (longer.length === 0) return 1;

  // Simple bigram overlap
  const bigramsA = new Set<string>();
  for (let i = 0; i < a.length - 1; i++) bigramsA.add(a.substring(i, i + 2));
  const bigramsB = new Set<string>();
  for (let i = 0; i < b.length - 1; i++) bigramsB.add(b.substring(i, i + 2));

  let intersection = 0;
  for (const bg of bigramsA) {
    if (bigramsB.has(bg)) intersection++;
  }

  return (2 * intersection) / (bigramsA.size + bigramsB.size);
}

// ── Helpers ──────────────────────────────────────────────────────

async function writeSuggestion(
  supabase: ReturnType<typeof createAdminClient>,
  reconId: string,
  candidate: ScoredCandidate,
) {
  await supabase
    .from("momo_reconciliations")
    .update({
      match_status: "suggested",
      metadata: {
        suggested_group_id: candidate.group_id,
        suggested_member_user_id: candidate.user_id,
        suggested_member_name: candidate.display_name,
        suggested_confidence: candidate.score,
        ai_reasoning: candidate.reasoning,
      },
      updated_at: new Date().toISOString(),
    })
    .eq("id", reconId);
}
