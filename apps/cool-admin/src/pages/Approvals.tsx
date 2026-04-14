import { Search, Filter, CheckCircle2, XCircle, Eye, Loader2, RefreshCw, AlertTriangle, Inbox, ShieldAlert, Clock, ThumbsUp } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { supabase } from "@/lib/supabase";
import { useAsyncData } from "@/lib/hooks";
import { toast } from "sonner";

interface AuditEntry {
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

export function Approvals() {
  const { data, loading, error, refetch } = useAsyncData(async () => {
    const { data, error } = await supabase.rpc("get_admin_audit_log", {
      p_limit: 50,
      p_offset: 0,
    });
    if (error) throw new Error(error.message);
    return data as AuditEntry[];
  });

  const { data: stats } = useAsyncData(async () => {
    const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
    const { count: total7d } = await supabase
      .from("admin_audit_log")
      .select("id", { count: "exact", head: true })
      .gte("created_at", weekAgo);

    const { count: approvals } = await supabase
      .from("admin_audit_log")
      .select("id", { count: "exact", head: true })
      .eq("action", "approve")
      .gte("created_at", weekAgo);

    const { count: rejections } = await supabase
      .from("admin_audit_log")
      .select("id", { count: "exact", head: true })
      .eq("action", "reject")
      .gte("created_at", weekAgo);

    return { total7d: total7d ?? 0, approvals: approvals ?? 0, rejections: rejections ?? 0 };
  });

  if (loading) {
    return <div className="flex h-96 items-center justify-center"><Loader2 className="h-8 w-8 animate-spin text-indigo-600" /></div>;
  }
  if (error) {
    return <div className="flex h-96 flex-col items-center justify-center gap-4"><AlertTriangle className="h-10 w-10 text-amber-500" /><p className="text-sm text-zinc-600">{error}</p><Button onClick={refetch} variant="outline" size="sm"><RefreshCw className="h-4 w-4 mr-2" /> Retry</Button></div>;
  }

  const entries = data ?? [];

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-zinc-900">Admin Audit Log</h1>
          <p className="text-sm text-zinc-500 mt-1">Review administrative actions and approval workflows.</p>
        </div>
        <Button onClick={refetch} variant="outline" size="sm"><RefreshCw className="h-4 w-4 mr-2" /> Refresh</Button>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-zinc-500">Actions (7d)</CardTitle>
            <Clock className="h-4 w-4 text-zinc-400" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-zinc-900">{stats?.total7d ?? 0}</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-zinc-500">Approvals (7d)</CardTitle>
            <ThumbsUp className="h-4 w-4 text-emerald-500" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-emerald-600">{stats?.approvals ?? 0}</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-zinc-500">Rejections (7d)</CardTitle>
            <ShieldAlert className="h-4 w-4 text-rose-500" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-rose-600">{stats?.rejections ?? 0}</div>
          </CardContent>
        </Card>
      </div>

      <Card>
        <div className="p-4 border-b border-zinc-100 flex items-center gap-3">
          <div className="relative w-full max-w-sm">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-zinc-400" />
            <Input className="pl-9" placeholder="Search audit log..." onChange={(e) => {
              if (e.target.value.length > 2) toast.info("Server-side search coming soon.");
            }} />
          </div>
          <Button variant="outline" size="icon" onClick={() => toast.info("Advanced filters coming soon.")}><Filter className="h-4 w-4" /></Button>
        </div>

        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Actor</TableHead>
              <TableHead>Phone</TableHead>
              <TableHead>Action</TableHead>
              <TableHead>Target</TableHead>
              <TableHead>Notes</TableHead>
              <TableHead>Time</TableHead>
              <TableHead className="text-right">Details</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {entries.length === 0 ? (
              <TableRow><TableCell colSpan={7} className="h-32 text-center"><div className="flex flex-col items-center gap-2 text-zinc-400"><Inbox className="h-8 w-8" /><p className="text-sm">No audit entries yet</p></div></TableCell></TableRow>
            ) : entries.map((e) => (
              <TableRow key={e.id}>
                <TableCell className="font-medium text-zinc-900">{e.actor_name || "(System)"}</TableCell>
                <TableCell className="font-mono text-xs text-zinc-500">{e.actor_phone || "—"}</TableCell>
                <TableCell>
                  <Badge variant={
                    e.action === "approve" ? "success" :
                    e.action === "reject" || e.action === "revoke" ? "danger" :
                    "outline"
                  } className="capitalize">
                    {e.action}
                  </Badge>
                </TableCell>
                <TableCell className="text-sm text-zinc-600">{e.target_table}{e.target_id ? ` / ${e.target_id.slice(0, 8)}…` : ""}</TableCell>
                <TableCell className="text-sm text-zinc-500 max-w-[200px] truncate">{e.notes ?? "—"}</TableCell>
                <TableCell className="text-sm text-zinc-500">{new Date(e.created_at).toLocaleString()}</TableCell>
                <TableCell className="text-right">
                  <Button variant="ghost" size="icon" onClick={() => toast.info("Audit detail view coming soon.")}><Eye className="h-4 w-4 text-zinc-400" /></Button>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </Card>
    </div>
  );
}
