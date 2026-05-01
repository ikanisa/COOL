import { supabase } from "@/lib/supabase";

export interface ReconciliationRow {
  group_id: string;
  group_name: string;
  type: string;
  member_count: number;
  monthly_contribution: number;
  expected_monthly: number;
  total_collected: number;
  target_amount: number;
  confirmed_30d: number;
  pending_count: number;
  gap_amount: number;
  gap_pct: number;
  bank_partner: string | null;
  created_at: string;
}

export interface HealthEvent {
  id: string;
  service: string;
  component: string;
  severity: string;
  message: string;
  metadata: Record<string, unknown>;
  created_at: string;
}

export interface HealthStats {
  total: number;
  last24h: number;
  warnings: number;
}

export interface AuditEntry {
  id: string;
  actor_id: string;
  actor_name: string;
  actor_phone: string;
  action: string;
  target_table: string;
  target_id: string;
  notes: string | null;
  created_at: string;
  total_count: number;
}

export interface AuditStats {
  total7d: number;
  approvals: number;
  rejections: number;
}

export interface BioPaySummary {
  total_profiles: number;
  active_profiles: number;
  revoked_profiles: number;
  total_matches_24h: number;
  successful_matches_24h: number;
  failed_matches_24h: number;
  avg_match_score_7d: number;
  enrollments_7d: number;
  revocations_7d: number;
  active_embeddings: number;
  payment_intents_24h: number;
  recent_enrollments: Array<{
    profile_id: string;
    public_id: string;
    display_name: string;
    country_code: string;
    route_type: string;
    enrolled_at: string;
  }>;
}

export async function getReconciliationSummary(): Promise<
  ReconciliationRow[]
> {
  const { data, error } = await supabase.rpc(
    "get_financial_reconciliation_summary"
  );
  if (error) throw new Error(error.message);
  return (data ?? []) as ReconciliationRow[];
}

export async function getBioPaySummary(): Promise<BioPaySummary> {
  const { data, error } = await supabase.rpc("get_biopay_admin_summary");
  if (error) throw new Error(error.message);
  return data as BioPaySummary;
}

export async function listHealthEvents(): Promise<HealthEvent[]> {
  const { data, error } = await supabase
    .from("operational_health_events")
    .select("id, service, component, severity, message, metadata, created_at")
    .order("created_at", { ascending: false })
    .limit(50);
  if (error) throw new Error(error.message);
  return (data ?? []) as HealthEvent[];
}

export async function getHealthStats(): Promise<HealthStats> {
  const oneDayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const [{ count: total }, { count: last24h }, { count: warnings }] =
    await Promise.all([
      supabase
        .from("operational_health_events")
        .select("id", { count: "exact", head: true }),
      supabase
        .from("operational_health_events")
        .select("id", { count: "exact", head: true })
        .gte("created_at", oneDayAgo),
      supabase
        .from("operational_health_events")
        .select("id", { count: "exact", head: true })
        .in("severity", ["warning", "error", "critical"])
        .gte("created_at", oneDayAgo),
    ]);

  return {
    total: total ?? 0,
    last24h: last24h ?? 0,
    warnings: warnings ?? 0,
  };
}

export async function listAuditEntries(): Promise<AuditEntry[]> {
  const { data, error } = await supabase.rpc("get_admin_audit_log", {
    p_limit: 50,
    p_offset: 0,
  });
  if (error) throw new Error(error.message);
  return (data ?? []) as AuditEntry[];
}

export async function getAuditStats(): Promise<AuditStats> {
  const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
  const [{ count: total7d }, { count: approvals }, { count: rejections }] =
    await Promise.all([
      supabase
        .from("admin_audit_log")
        .select("id", { count: "exact", head: true })
        .gte("created_at", weekAgo),
      supabase
        .from("admin_audit_log")
        .select("id", { count: "exact", head: true })
        .eq("action", "approve")
        .gte("created_at", weekAgo),
      supabase
        .from("admin_audit_log")
        .select("id", { count: "exact", head: true })
        .eq("action", "reject")
        .gte("created_at", weekAgo),
    ]);

  return {
    total7d: total7d ?? 0,
    approvals: approvals ?? 0,
    rejections: rejections ?? 0,
  };
}
