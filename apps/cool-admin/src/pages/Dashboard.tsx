import { Users, Landmark, DollarSign, TrendingUp, ArrowUpRight, ShieldCheck, Loader2, RefreshCw, AlertTriangle } from "lucide-react";
import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from "recharts";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { supabase } from "@/lib/supabase";
import { useAsyncData } from "@/lib/hooks";

interface PlatformAnalytics {
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

async function fetchAnalytics(): Promise<PlatformAnalytics> {
  const { data, error } = await supabase.rpc("get_platform_analytics_summary");
  if (error) throw new Error(error.message);
  return data as PlatformAnalytics;
}

async function fetchChartData() {
  const thirtyDaysAgo = new Date();
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

  const { data, error } = await supabase
    .from("group_contributions")
    .select("amount, status, created_at")
    .gte("created_at", thirtyDaysAgo.toISOString())
    .eq("status", "confirmed")
    .order("created_at", { ascending: true });

  if (error) throw new Error(error.message);

  // Aggregate by day
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

function formatNumber(n: number | undefined): string {
  if (n == null) return "—";
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
  return n.toLocaleString();
}

function formatRWF(n: number | undefined): string {
  if (n == null) return "—";
  return n.toLocaleString() + " RWF";
}

export function Dashboard() {
  const { data: analytics, loading, error, refetch } = useAsyncData(fetchAnalytics);
  const { data: chartData, loading: chartLoading } = useAsyncData(fetchChartData);

  if (loading) {
    return (
      <div className="flex h-96 items-center justify-center">
        <Loader2 className="h-8 w-8 animate-spin text-indigo-600" />
        <span className="ml-3 text-zinc-500">Loading dashboard…</span>
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex h-96 flex-col items-center justify-center gap-4">
        <AlertTriangle className="h-10 w-10 text-amber-500" />
        <p className="text-sm text-zinc-600">{error}</p>
        <Button onClick={refetch} variant="outline" size="sm">
          <RefreshCw className="h-4 w-4 mr-2" />
          Retry
        </Button>
      </div>
    );
  }

  const kpis = [
    {
      title: "Total Users",
      value: formatNumber(analytics?.real_users),
      subtitle: `+${analytics?.signups_7d ?? 0} this week`,
      icon: Users,
      color: "text-indigo-600",
      bg: "bg-indigo-50",
    },
    {
      title: "Active Groups",
      value: formatNumber(analytics?.active_groups),
      subtitle: `${formatNumber(analytics?.total_groups)} total`,
      icon: Landmark,
      color: "text-emerald-600",
      bg: "bg-emerald-50",
    },
    {
      title: "Total Partners",
      value: formatNumber(analytics?.active_partners),
      subtitle: `${formatNumber(analytics?.total_partners)} registered`,
      icon: DollarSign,
      color: "text-amber-600",
      bg: "bg-amber-50",
    },
    {
      title: "Platform Admins",
      value: formatNumber(analytics?.total_admins),
      subtitle: `${analytics?.audit_actions_7d ?? 0} actions this week`,
      icon: ShieldCheck,
      color: "text-rose-600",
      bg: "bg-rose-50",
    },
  ];

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-zinc-900">Dashboard</h1>
          <p className="text-sm text-zinc-500 mt-1">
            Platform overview •{" "}
            {analytics?.generated_at
              ? new Date(analytics.generated_at).toLocaleString()
              : "Live"}
          </p>
        </div>
        <Button onClick={refetch} variant="outline" size="sm">
          <RefreshCw className="h-4 w-4 mr-2" />
          Refresh
        </Button>
      </div>

      {/* KPI Cards */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {kpis.map((kpi) => (
          <Card key={kpi.title}>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium text-zinc-500">{kpi.title}</CardTitle>
              <div className={`rounded-lg ${kpi.bg} p-2`}>
                <kpi.icon className={`h-4 w-4 ${kpi.color}`} />
              </div>
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold text-zinc-900">{kpi.value}</div>
              <p className="text-xs text-zinc-500 mt-1 flex items-center gap-1">
                <ArrowUpRight className="h-3 w-3 text-emerald-500" />
                {kpi.subtitle}
              </p>
            </CardContent>
          </Card>
        ))}
      </div>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-5">
        {/* Chart */}
        <Card className="lg:col-span-3">
          <CardHeader>
            <CardTitle>Confirmed Contributions</CardTitle>
            <CardDescription>Last 30 days, aggregated by day (RWF)</CardDescription>
          </CardHeader>
          <CardContent>
            <div className="h-80">
              {chartLoading ? (
                <div className="flex h-full items-center justify-center">
                  <Loader2 className="h-6 w-6 animate-spin text-zinc-400" />
                </div>
              ) : chartData && chartData.length > 0 ? (
                <ResponsiveContainer width="100%" height="100%">
                  <AreaChart data={chartData}>
                    <defs>
                      <linearGradient id="colorAmount" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="5%" stopColor="var(--color-brand-600, #4f46e5)" stopOpacity={0.2} />
                        <stop offset="95%" stopColor="var(--color-brand-600, #4f46e5)" stopOpacity={0} />
                      </linearGradient>
                    </defs>
                    <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
                    <XAxis dataKey="name" fontSize={12} tickLine={false} axisLine={false} />
                    <YAxis
                      fontSize={12}
                      tickLine={false}
                      axisLine={false}
                      tickFormatter={(v: number) => formatNumber(v)}
                    />
                    <Tooltip
                      formatter={(value) => [formatRWF(value as number), "Amount"]}
                      contentStyle={{
                        borderRadius: "12px",
                        border: "1px solid #e2e8f0",
                        boxShadow: "0 4px 12px rgba(0,0,0,0.08)",
                      }}
                    />
                    <Area
                      type="monotone"
                      dataKey="amount"
                      stroke="var(--color-brand-600, #4f46e5)"
                      strokeWidth={2}
                      fillOpacity={1}
                      fill="url(#colorAmount)"
                    />
                  </AreaChart>
                </ResponsiveContainer>
              ) : (
                <div className="flex h-full flex-col items-center justify-center text-zinc-400">
                  <TrendingUp className="h-8 w-8 mb-2" />
                  <p className="text-sm">No contribution data yet</p>
                </div>
              )}
            </div>
          </CardContent>
        </Card>

        {/* Role Distribution + Events */}
        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle>Quick Stats</CardTitle>
          </CardHeader>
          <CardContent className="space-y-6">
            <div>
              <h4 className="text-xs font-medium text-zinc-500 uppercase tracking-wider mb-3">Role Distribution</h4>
              <div className="space-y-2">
                {analytics?.role_distribution &&
                  Object.entries(analytics.role_distribution).map(([role, count]) => (
                    <div key={role} className="flex items-center justify-between">
                      <Badge variant="outline" className="capitalize">{role}</Badge>
                      <span className="text-sm font-bold text-zinc-900">{count}</span>
                    </div>
                  ))}
                {(!analytics?.role_distribution || Object.keys(analytics.role_distribution).length === 0) && (
                  <p className="text-sm text-zinc-400">No role assignments</p>
                )}
              </div>
            </div>

            <div className="border-t border-zinc-100 pt-4">
              <h4 className="text-xs font-medium text-zinc-500 uppercase tracking-wider mb-3">Top Events (30d)</h4>
              <div className="space-y-2">
                {analytics?.event_distribution &&
                  Object.entries(analytics.event_distribution)
                    .sort(([, a], [, b]) => b - a)
                    .slice(0, 5)
                    .map(([event, count]) => (
                      <div key={event} className="flex items-center justify-between">
                        <span className="text-sm text-zinc-600 truncate max-w-[160px]">{event}</span>
                        <span className="text-sm font-medium text-zinc-900">{formatNumber(count)}</span>
                      </div>
                    ))}
                {(!analytics?.event_distribution || Object.keys(analytics.event_distribution).length === 0) && (
                  <p className="text-sm text-zinc-400">No events recorded</p>
                )}
              </div>
            </div>

            <div className="border-t border-zinc-100 pt-4">
              <h4 className="text-xs font-medium text-zinc-500 uppercase tracking-wider mb-3">Data Quality</h4>
              <div className="space-y-2">
                <div className="flex items-center justify-between">
                  <span className="text-sm text-zinc-600">Mock Users</span>
                  <span className="text-sm font-medium text-zinc-900">{analytics?.mock_users ?? 0}</span>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-sm text-zinc-600">Real Users</span>
                  <span className="text-sm font-bold text-emerald-600">{analytics?.real_users ?? 0}</span>
                </div>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
