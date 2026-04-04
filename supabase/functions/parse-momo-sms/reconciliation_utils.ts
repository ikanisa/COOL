/**
 * reconciliation_utils.ts — Shared types, utilities, and scoring functions
 * used by all reconciler modules.
 */

import { type ParsedSms, type RawSmsRecord } from "./ai_parser.ts";

// ── Types ──────────────────────────────────────────────────────
export type GroupContributionRecord = {
  id: string;
  group_id: string | null;
  status: string | null;
};

export type GroupRouteRecord = {
  id: string;
  name: string;
  type: string | null;
  receiving_momo_code: string | null;
  momo_number: string | null;
  receiving_momo_route_type: string | null;
};

export type PartnerRouteRecord = {
  id: string;
  partner_id: string;
  partner_name: string | null;
  partner_slug: string | null;
  recipient_code: string | null;
  reconciliation_label: string | null;
  status: string | null;
};

export type GroupContributionCandidateRecord = {
  id: string;
  group_id: string | null;
  status: string | null;
  momo_reference: string | null;
  created_at: string | null;
  route_digits: string | null;
};

export type AutoReconciliationResult = {
  matchType: string;
  matchStatus: "matched" | "pending_review" | "manual_review";
  ledgerStatus: "draft" | "posted";
  targetTable: string | null;
  targetRecordId: string | null;
  matchedReference: string | null;
  notes: string | null;
  metadata: Record<string, unknown>;
};

// ── Utility functions ──────────────────────────────────────────
export function asString(value: unknown): string | null {
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }
  return null;
}

export function asRecord(value: unknown): Record<string, unknown> | null {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return null;
}

export function asNullableInt(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.round(value);
  }
  if (typeof value === "string") {
    const cleaned = value.replaceAll(/[^\d.-]/g, "");
    if (!cleaned) return null;
    const parsed = Number.parseFloat(cleaned);
    return Number.isFinite(parsed) ? Math.round(parsed) : null;
  }
  return null;
}

export function normalizeProviderId(
  value: string | null | undefined,
): string | null {
  const normalized = value?.trim().toLowerCase();
  switch (normalized) {
    case "mtn":
    case "mtn rwanda":
    case "mtn_rwanda":
      return "mtn_rwanda";
    case "airtel":
      return "airtel";
    case "orange":
      return "orange";
    default:
      return normalized?.length ? normalized : null;
  }
}

export function normalizeDigits(
  value: string | null | undefined,
): string | null {
  if (!value) {
    return null;
  }
  const digits = value.replaceAll(/\D/g, "");
  return digits.length > 0 ? digits : null;
}

export function digitsMatch(
  left: string | null,
  right: string | null,
): boolean {
  if (!left || !right) {
    return false;
  }
  return left === right || left.endsWith(right) || right.endsWith(left);
}

export function payeeRouteDigits(parsed: ParsedSms): string | null {
  return normalizeDigits(parsed.payee_number_or_code) ??
    normalizeDigits(parsed.merchant_code);
}

export function parseIsoDate(value: string | null | undefined): Date | null {
  if (!value) {
    return null;
  }
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

export function candidateTimestamp(
  parsed: ParsedSms,
  rawSms: RawSmsRecord,
): Date | null {
  return parseIsoDate(parsed.tx_datetime_iso) ??
    parseIsoDate(rawSms.sms_received_at);
}

export function sourceReference(
  rawSms: RawSmsRecord,
  parsed: ParsedSms,
): string {
  return parsed.momo_tx_id ?? rawSms.detected_tx_id ?? `SMS-${rawSms.id}`;
}

export function buildDirectCandidateScore(
  status: string | null,
  createdAt: string | null,
  payeeDigits: string | null,
  routeDigits: string | null,
  parsed: ParsedSms,
  rawSms: RawSmsRecord,
): number {
  let score = 0;
  const normalizedStatus = status?.trim().toLowerCase();
  if (normalizedStatus === "pending") {
    score += 30;
  } else if (
    normalizedStatus === "confirmed" ||
    normalizedStatus === "completed" ||
    normalizedStatus === "active" ||
    normalizedStatus === "paid" ||
    normalizedStatus === "valid"
  ) {
    // Downgraded so it cannot be a hard auto-allocation without being 'pending'
    score -= 20;
  } else {
    score -= 50;
  }

  const smsTime = candidateTimestamp(parsed, rawSms);
  const createdAtDate = parseIsoDate(createdAt);
  if (smsTime && createdAtDate) {
    const deltaMs = Math.abs(smsTime.getTime() - createdAtDate.getTime());
    if (deltaMs <= 10 * 60 * 1000) {
      score += 24;
    } else if (deltaMs <= 60 * 60 * 1000) {
      score += 18;
    } else if (deltaMs <= 6 * 60 * 60 * 1000) {
      score += 10;
    } else if (deltaMs <= 24 * 60 * 60 * 1000) {
      score += 4;
    } else {
      score -= 25;
    }
  }

  if (payeeDigits && routeDigits) {
    if (digitsMatch(routeDigits, payeeDigits)) {
      score += 14;
    } else if (
      routeDigits.length >= 3 &&
      payeeDigits.length >= 3 &&
      routeDigits.slice(-3) === payeeDigits.slice(-3)
    ) {
      score += 6;
    } else {
      score -= 10;
    }
  }

  return score;
}

export function chooseBestCandidate<T>(
  scored: Array<{ candidate: T; score: number; key: string }>,
): {
  candidate: T | null;
  score: number | null;
  ambiguous: boolean;
} {
  const ranked = scored.sort((left, right) => right.score - left.score);
  const best = ranked[0];
  if (!best || best.score < 15) {
    return { candidate: null, score: best?.score ?? null, ambiguous: false };
  }

  const second = ranked[1];
  if (
    second &&
    second.key !== best.key &&
    second.score >= 15 &&
    Math.abs(best.score - second.score) <= 2
  ) {
    return { candidate: null, score: best.score, ambiguous: true };
  }

  return { candidate: best.candidate, score: best.score, ambiguous: false };
}

export function asGroupRouteRecord(
  value: Record<string, unknown>,
): GroupRouteRecord {
  return {
    id: asString(value["id"]) ?? "",
    name: asString(value["name"]) ?? "Savings group",
    type: asString(value["type"]),
    receiving_momo_code: asString(value["receiving_momo_code"]),
    momo_number: asString(value["momo_number"]),
    receiving_momo_route_type: asString(value["receiving_momo_route_type"]),
  };
}

export function asPartnerRouteRecord(
  value: Record<string, unknown>,
): PartnerRouteRecord {
  const partner = asRecord(value["partners"]);
  return {
    id: asString(value["id"]) ?? "",
    partner_id: asString(value["partner_id"]) ?? "",
    partner_name: asString(partner?.["name"]),
    partner_slug: asString(partner?.["slug"]),
    recipient_code: asString(value["recipient_code"]),
    reconciliation_label: asString(value["reconciliation_label"]),
    status: asString(value["status"]),
  };
}

export function buildManualReviewResult(
  reason: string,
  metadata: Record<string, unknown> = {},
): AutoReconciliationResult {
  return {
    matchType: "manual_review",
    matchStatus: "manual_review",
    ledgerStatus: "draft",
    targetTable: null,
    targetRecordId: null,
    matchedReference: null,
    notes: reason,
    metadata: {
      auto_match: false,
      ...metadata,
    },
  };
}

export function ledgerEntryType(parsed: ParsedSms): "credit" | "debit" {
  return parsed.tx_direction === "credit" ? "credit" : "debit";
}
