import { Activity, Server, Smartphone, ShieldCheck, AlertTriangle as AlertTriangleIcon, CheckCircle, Loader2, RefreshCw } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { supabase } from "@/lib/supabase";
import { useAsyncData } from "@/lib/hooks";

interface HealthEvent {
  id: string;
  service: string;
  component: string;
  severity: string;
  message: string;
  metadata: Record<string, unknown>;
  created_at: string;
}

export function Health() {
  const { data: events, loading, error, refetch } = useAsyncData(async () => {
    const { data, error } = await supabase
      .from("operational_health_events")
      .select("id, service, component, severity, message, metadata, created_at")
      .order("created_at", { ascending: false })
      .limit(50);
    if (error) throw new Error(error.message);
    return data as HealthEvent[];
  });

  const { data: stats } = useAsyncData(async () => {
    const { count: total } = await supabase
      .from("operational_health_events")
      .select("id", { count: "exact", head: true });

    const oneDayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    const { count: last24h } = await supabase
      .from("operational_health_events")
      .select("id", { count: "exact", head: true })
      .gte("created_at", oneDayAgo);

    const { count: warnings } = await supabase
      .from("operational_health_events")
      .select("id", { count: "exact", head: true })
      .in("severity", ["warning", "error", "critical"])
      .gte("created_at", oneDayAgo);

    return { total: total ?? 0, last24h: last24h ?? 0, warnings: warnings ?? 0 };
  });

  if (loading) {
    return <div className="flex h-96 items-center justify-center"><Loader2 className="h-8 w-8 animate-spin text-indigo-600" /></div>;
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-zinc-900">System Health</h1>
          <p className="text-sm text-zinc-500 mt-1">Operational dashboard for platform services and edge functions.</p>
        </div>
        <Button onClick={refetch} variant="outline" size="sm"><RefreshCw className="h-4 w-4 mr-2" /> Refresh</Button>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-zinc-500">System Status</CardTitle>
            <ShieldCheck className="h-4 w-4 text-emerald-500" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-emerald-600">
              {(stats?.warnings ?? 0) === 0 ? "All Clear" : "Issues Detected"}
            </div>
            <p className="text-xs text-zinc-500 mt-1">{stats?.warnings ?? 0} warnings in 24h</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-zinc-500">Events (24h)</CardTitle>
            <Activity className="h-4 w-4 text-zinc-400" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-zinc-900">{stats?.last24h ?? 0}</div>
            <p className="text-xs text-zinc-500 mt-1">{stats?.total ?? 0} total events</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-zinc-500">Edge Functions</CardTitle>
            <Server className="h-4 w-4 text-zinc-400" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-zinc-900">16</div>
            <p className="text-xs text-zinc-500 mt-1">Deployed functions</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-zinc-500">SMS Pipeline</CardTitle>
            <Smartphone className="h-4 w-4 text-zinc-400" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-zinc-900">Active</div>
            <p className="text-xs text-emerald-600 mt-1 font-medium">parse-momo-sms running</p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Recent Operational Events</CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          {error ? (
            <div className="text-center py-8"><AlertTriangleIcon className="h-6 w-6 text-amber-500 mx-auto mb-2" /><p className="text-sm text-zinc-600">{error}</p></div>
          ) : (events ?? []).length === 0 ? (
            <div className="text-center py-8 text-zinc-400"><CheckCircle className="h-8 w-8 mx-auto mb-2" /><p className="text-sm">No operational events recorded</p></div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Severity</TableHead>
                  <TableHead>Service</TableHead>
                  <TableHead>Component</TableHead>
                  <TableHead>Message</TableHead>
                  <TableHead>Time</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {(events ?? []).slice(0, 20).map((evt) => (
                  <TableRow key={evt.id}>
                    <TableCell>
                      <Badge variant={
                        evt.severity === "error" || evt.severity === "critical" ? "danger" :
                        evt.severity === "warning" ? "warning" : "success"
                      }>
                        {evt.severity}
                      </Badge>
                    </TableCell>
                    <TableCell className="font-medium text-zinc-900">{evt.service ?? "—"}</TableCell>
                    <TableCell className="text-zinc-600">{evt.component ?? "—"}</TableCell>
                    <TableCell className="text-sm text-zinc-600 max-w-[300px] truncate">{evt.message}</TableCell>
                    <TableCell className="text-sm text-zinc-500">{new Date(evt.created_at).toLocaleString()}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
