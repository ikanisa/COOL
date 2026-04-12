import { useState } from "react";
import { AlertCircle, CheckCircle2, Search, Building2, Loader2, RefreshCw, AlertTriangle, Inbox } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { supabase } from "@/lib/supabase";
import { useAsyncData } from "@/lib/hooks";

interface ReconciliationRow {
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

export function Reconciliation() {
  const [search, setSearch] = useState("");

  const { data, loading, error, refetch } = useAsyncData(async () => {
    const { data, error } = await supabase.rpc("get_financial_reconciliation_summary");
    if (error) throw new Error(error.message);
    return data as ReconciliationRow[];
  });

  if (loading) {
    return <div className="flex h-96 items-center justify-center"><Loader2 className="h-8 w-8 animate-spin text-indigo-600" /></div>;
  }
  if (error) {
    return <div className="flex h-96 flex-col items-center justify-center gap-4"><AlertTriangle className="h-10 w-10 text-amber-500" /><p className="text-sm text-zinc-600">{error}</p><Button onClick={refetch} variant="outline" size="sm"><RefreshCw className="h-4 w-4 mr-2" /> Retry</Button></div>;
  }

  const groups = (data ?? []).filter(
    (g) => !search.trim() || g.group_name.toLowerCase().includes(search.toLowerCase())
  );

  const totalExpected = groups.reduce((s, g) => s + g.expected_monthly, 0);
  const totalCollected = groups.reduce((s, g) => s + g.total_collected, 0);
  const totalPending = groups.reduce((s, g) => s + g.pending_count, 0);
  const atRisk = groups.filter((g) => g.gap_pct > 50).length;

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-zinc-900">Financial Reconciliation</h1>
          <p className="text-sm text-zinc-500 mt-1">Savings group collection health and gap analysis.</p>
        </div>
        <Button onClick={refetch} variant="outline" size="sm"><RefreshCw className="h-4 w-4 mr-2" /> Refresh</Button>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-zinc-500">Groups Tracked</CardTitle>
            <Building2 className="h-4 w-4 text-indigo-500" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-zinc-900">{groups.length}</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-zinc-500">Expected Monthly</CardTitle>
            <CheckCircle2 className="h-4 w-4 text-emerald-500" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-zinc-900">{totalExpected.toLocaleString()}</div>
            <p className="text-xs text-zinc-500 mt-1">RWF</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-zinc-500">Total Collected</CardTitle>
            <CheckCircle2 className="h-4 w-4 text-emerald-500" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-emerald-600">{totalCollected.toLocaleString()}</div>
            <p className="text-xs text-zinc-500 mt-1">RWF • {totalPending} pending</p>
          </CardContent>
        </Card>
        <Card className={atRisk > 0 ? "border-amber-200 bg-amber-50/30" : ""}>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-zinc-500">At Risk Groups</CardTitle>
            <AlertCircle className="h-4 w-4 text-amber-500" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-amber-700">{atRisk}</div>
            <p className="text-xs text-amber-600 mt-1">&gt;50% collection gap</p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <div className="p-4 border-b border-zinc-100 flex items-center gap-3">
          <div className="relative w-full max-w-sm">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-zinc-400" />
            <Input className="pl-9" placeholder="Search groups..." value={search} onChange={(e) => setSearch(e.target.value)} />
          </div>
        </div>
        <div className="px-4 py-2 bg-zinc-50/50 border-b border-zinc-100 text-xs font-medium text-zinc-500 flex justify-end">* All values in RWF</div>

        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Group</TableHead>
              <TableHead>Members</TableHead>
              <TableHead>Monthly/Member</TableHead>
              <TableHead>Expected</TableHead>
              <TableHead>Collected</TableHead>
              <TableHead>Confirmed (30d)</TableHead>
              <TableHead>Pending</TableHead>
              <TableHead>Gap %</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {groups.length === 0 ? (
              <TableRow><TableCell colSpan={8} className="h-32 text-center"><div className="flex flex-col items-center gap-2 text-zinc-400"><Inbox className="h-8 w-8" /><p className="text-sm">No groups with contribution targets</p></div></TableCell></TableRow>
            ) : groups.map((g) => (
              <TableRow key={g.group_id}>
                <TableCell>
                  <div>
                    <p className="font-medium text-zinc-900">{g.group_name}</p>
                    {g.bank_partner && <p className="text-xs text-zinc-500">{g.bank_partner}</p>}
                  </div>
                </TableCell>
                <TableCell className="text-zinc-600">{g.member_count}</TableCell>
                <TableCell className="text-zinc-600">{g.monthly_contribution.toLocaleString()}</TableCell>
                <TableCell className="font-medium text-zinc-900">{g.expected_monthly.toLocaleString()}</TableCell>
                <TableCell className="font-bold text-emerald-600">{g.total_collected.toLocaleString()}</TableCell>
                <TableCell className="text-zinc-600">{g.confirmed_30d.toLocaleString()}</TableCell>
                <TableCell>
                  {g.pending_count > 0 ? (
                    <Badge variant="warning">{g.pending_count}</Badge>
                  ) : (
                    <span className="text-zinc-400">0</span>
                  )}
                </TableCell>
                <TableCell>
                  <Badge variant={g.gap_pct > 50 ? "danger" : g.gap_pct > 20 ? "warning" : "success"}>
                    {g.gap_pct}%
                  </Badge>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </Card>
    </div>
  );
}
