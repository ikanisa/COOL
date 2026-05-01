import { supabase } from "@/lib/supabase";

export interface PlatformAnalytics {
  total_users: number;
  total_groups: number;
  total_partners: number;
  total_admins: number;
  mock_users: number;
  real_users: number;
  signups_7d: number;
  signups_30d: number;
  active_groups: number;
  active_partners: number;
  role_distribution: Record<string, number>;
  event_distribution: Record<string, number>;
  audit_actions_7d: number;
  generated_at: string;
}

export interface ContributionChartPoint {
  name: string;
  amount: number;
}

export async function getPlatformAnalytics(): Promise<PlatformAnalytics> {
  const { data, error } = await supabase.rpc("get_platform_analytics_summary");
  if (error) throw new Error(error.message);
  return data as PlatformAnalytics;
}

export async function getContributionChartData(): Promise<
  ContributionChartPoint[]
> {
  const thirtyDaysAgo = new Date();
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

  const { data, error } = await supabase
    .from("group_contributions")
    .select("amount, status, created_at")
    .gte("created_at", thirtyDaysAgo.toISOString())
    .eq("status", "confirmed")
    .order("created_at", { ascending: true });

  if (error) throw new Error(error.message);

  const byDay = new Map<string, number>();
  (data ?? []).forEach((row) => {
    const day = new Date(row.created_at).toLocaleDateString("en-US", {
      month: "short",
      day: "numeric",
    });
    byDay.set(day, (byDay.get(day) ?? 0) + (row.amount ?? 0));
  });

  return Array.from(byDay.entries()).map(([name, amount]) => ({
    name,
    amount,
  }));
}
