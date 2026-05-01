import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { createAdminClient, createUserClient } from "../_shared/supabase.ts";

type AdminClient = ReturnType<typeof createAdminClient>;
type UserClient = ReturnType<typeof createUserClient>;

export interface AllocateContributionsHandlerDependencies {
  createAdminClient: () => AdminClient;
  createUserClient: (authorization: string) => UserClient;
  getGeminiApiKey: () => string;
}

const defaultDeps: AllocateContributionsHandlerDependencies = {
  createAdminClient,
  createUserClient,
  getGeminiApiKey: () => Deno.env.get("GEMINI_API_KEY") ?? "",
};

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

interface ScopedManualReview {
  review_id: string;
}

class HttpError extends Error {
  constructor(public readonly status: number, message: string) {
    super(message);
  }
}

export function createAllocateContributionsHandler(
  deps: AllocateContributionsHandlerDependencies = defaultDeps,
) {
  return async (req: Request): Promise<Response> => {
    const corsResponse = handleCors(req);
    if (corsResponse) {
      return corsResponse;
    }

    if (req.method !== "POST") {
      return methodNotAllowed("POST");
    }

    try {
      const authorization = req.headers.get("authorization")?.trim() ??
        req.headers.get("Authorization")?.trim();
      if (!authorization) {
        return errorResponse("Authentication required", 401);
      }

      const userClient = deps.createUserClient(authorization);
      await requireCaller(userClient);

      const { partner_id } = await req.json().catch(() => ({
        partner_id: null,
      }));
      const partnerId = normalizePartnerId(partner_id);
      if (!partnerId) {
        return errorResponse("partner_id is required", 400);
      }

      const adminClient = deps.createAdminClient();

      // 1. Fetch only reviews visible in the caller's bank workspace. This RPC
      // runs with the user's JWT so auth.uid() and bank custody guards apply.
      const { data: scopedReviews, error: scopedReviewErr } = await userClient
        .rpc("get_bank_manual_review_allocations", {
          p_partner_id: partnerId,
          p_limit: 50,
          p_offset: 0,
        });

      if (scopedReviewErr) {
        return jsonResponse(
          { error: scopedReviewErr.message },
          rpcErrorStatus(scopedReviewErr.message),
        );
      }

      const reviewIds = ((scopedReviews ?? []) as ScopedManualReview[])
        .map((review) => review.review_id)
        .filter(Boolean);

      if (reviewIds.length === 0) {
        return jsonResponse({
          message: "No unresolved allocations found.",
          processed: 0,
        });
      }

      const { data: recons, error: reconErr } = await adminClient
        .from("momo_reconciliations")
        .select("id, match_status, parsed_sms_id, metadata")
        .in("id", reviewIds)
        .in("match_status", ["pending_review", "manual_review", "suggested"])
        .order("created_at", { ascending: false })
        .limit(50);

      if (reconErr) {
        return jsonResponse({ error: reconErr.message }, 500);
      }

      if (!recons || recons.length === 0) {
        return jsonResponse({
          message: "No unresolved allocations found.",
          processed: 0,
        });
      }

      // 2. Fetch parsed SMS data for these reconciliations
      const parsedIds = recons.map((r: ReconRow) => r.parsed_sms_id).filter(
        Boolean,
      );
      const { data: parsedList } = await adminClient
        .from("momo_sms_parsed")
        .select("id, amount, payer_phone, payer_name, momo_tx_id, payee_phone")
        .in("id", parsedIds);

      const parsedMap = new Map<string, ParsedSms>();
      for (const p of parsedList ?? []) {
        parsedMap.set(p.id, p);
      }

      // 3. Fetch only members in the same bank workspace. There is no unscoped
      // direct-query fallback because suggestions contain member identity data.
      const membersResult = await userClient.rpc(
        "get_bank_all_group_members_for_matching",
        {
          p_partner_id: partnerId,
        },
      );

      if (membersResult.error) {
        return jsonResponse(
          { error: membersResult.error.message },
          rpcErrorStatus(membersResult.error.message),
        );
      }

      const memberList: GroupMember[] =
        (membersResult.data ?? []) as GroupMember[];

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
            const allocationResult = await userClient.rpc(
              "bank_allocate_manual_review_allocation",
              {
                p_partner_id: partnerId,
                p_review_id: recon.id,
                p_group_id: best.group_id,
                p_member_user_id: best.user_id,
                p_note:
                  `AI auto-allocated (${best.score}% confidence). ${best.reasoning}`,
              },
            );
            if (allocationResult.error) {
              throw new Error(allocationResult.error.message);
            }
            autoAllocated++;
          } catch {
            // If auto-allocate fails (e.g., auth issue), fall through to suggestion
            await writeSuggestion(userClient, partnerId, recon.id, best);
            suggested++;
          }
        } else if (best.score >= 40) {
          // Medium confidence: suggest for review
          await writeSuggestion(userClient, partnerId, recon.id, best);
          suggested++;
        }
        // Low confidence: leave as manual_review

        processed++;
      }

      // 5. If Gemini is available, do fuzzy name matching on remaining unresolved
      if (deps.getGeminiApiKey()) {
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
  };
}

async function requireCaller(
  userClient: UserClient,
): Promise<void> {
  const {
    data: { user },
    error,
  } = await userClient.auth.getUser();

  if (error || !user) {
    throw new HttpError(401, "Authentication required");
  }
}

function normalizePartnerId(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function rpcErrorStatus(message: string): number {
  const normalized = message.toLowerCase();
  if (
    normalized.includes("not authorized") ||
    normalized.includes("forbidden")
  ) {
    return 403;
  }
  return 500;
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
  const matchingGroupIds = (recon.metadata?.matching_group_ids as string[]) ??
    [];

  for (const member of members) {
    let score = 0;
    const reasons: string[] = [];
    const memberPhone = normalizePhone(member.phone);

    // Phone match (strongest signal)
    if (payerPhone && memberPhone && payerPhone === memberPhone) {
      score += 45;
      reasons.push("exact phone match");
    } else if (
      payerPhone && memberPhone && payerPhone.endsWith(memberPhone.slice(-6))
    ) {
      score += 25;
      reasons.push("partial phone match (last 6 digits)");
    }

    // Name match
    if (payerName && member.display_name) {
      const memberName = member.display_name.toLowerCase().trim();
      if (payerName === memberName) {
        score += 30;
        reasons.push("exact name match");
      } else if (
        payerName.includes(memberName) || memberName.includes(payerName)
      ) {
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
      } else if (
        Math.abs(amount - member.contribution_amount) /
            member.contribution_amount < 0.1
      ) {
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
  if (a.length === 0 && b.length === 0) return 1;

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
  userClient: UserClient,
  partnerId: string,
  reconId: string,
  candidate: ScoredCandidate,
) {
  const { error } = await userClient.rpc(
    "bank_write_ai_allocation_suggestion",
    {
      p_partner_id: partnerId,
      p_review_id: reconId,
      p_group_id: candidate.group_id,
      p_member_user_id: candidate.user_id,
      p_confidence: candidate.score,
      p_reasoning: candidate.reasoning,
    },
  );

  if (error) {
    throw new HttpError(
      403,
      `Could not write allocation suggestion: ${error.message}`,
    );
  }
}

if (import.meta.main) {
  Deno.serve(createAllocateContributionsHandler());
}
