import { Fingerprint, Activity, ShieldAlert, UserX, Search, Filter, MoreHorizontal, Eye, Ban, RotateCcw, Loader2, RefreshCw, AlertTriangle, Inbox } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { supabase } from "@/lib/supabase";
import { useAsyncData } from "@/lib/hooks";

interface BioPaySummary {
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

export function BioPay() {
  const { data, loading, error, refetch } = useAsyncData(async () => {
    const { data, error } = await supabase.rpc("get_biopay_admin_summary");
    if (error) throw new Error(error.message);
    return data as BioPaySummary;
  });

  if (loading) {
    return <div className="flex h-96 items-center justify-center"><Loader2 className="h-8 w-8 animate-spin text-indigo-600" /></div>;
  }
  if (error) {
    return <div className="flex h-96 flex-col items-center justify-center gap-4"><AlertTriangle className="h-10 w-10 text-amber-500" /><p className="text-sm text-zinc-600">{error}</p><Button onClick={refetch} variant="outline" size="sm"><RefreshCw className="h-4 w-4 mr-2" /> Retry</Button></div>;
  }

  const matchRate = data && data.total_matches_24h > 0
    ? ((data.successful_matches_24h / data.total_matches_24h) * 100).toFixed(1)
    : "—";

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-zinc-900">BioPay Enrollments</h1>
          <p className="text-sm text-zinc-500 mt-1">Facial recognition profiles, match rates, and security management.</p>
        </div>
        <Button onClick={refetch} variant="outline" size="sm"><RefreshCw className="h-4 w-4 mr-2" /> Refresh</Button>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-zinc-500">Total Enrolled</CardTitle>
            <Fingerprint className="h-4 w-4 text-indigo-500" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-zinc-900">{(data?.total_profiles ?? 0).toLocaleString()}</div>
            <p className="text-xs text-emerald-600 mt-1 font-medium">+{data?.enrollments_7d ?? 0} this week</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-zinc-500">Match Rate (24h)</CardTitle>
            <Activity className="h-4 w-4 text-emerald-500" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-zinc-900">{matchRate}%</div>
            <p className="text-xs text-zinc-500 mt-1">{data?.total_matches_24h ?? 0} total attempts</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-zinc-500">Failed Matches (24h)</CardTitle>
            <ShieldAlert className="h-4 w-4 text-amber-500" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-zinc-900">{data?.failed_matches_24h ?? 0}</div>
            <p className="text-xs text-zinc-500 mt-1">Avg score: {data?.avg_match_score_7d ?? "—"}</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-zinc-500">Revoked Profiles</CardTitle>
            <UserX className="h-4 w-4 text-rose-500" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-zinc-900">{data?.revoked_profiles ?? 0}</div>
            <p className="text-xs text-zinc-500 mt-1">{data?.revocations_7d ?? 0} this week</p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <div className="flex flex-col sm:flex-row items-center justify-between p-4 border-b border-zinc-100 gap-4">
          <div className="flex items-center gap-3 w-full sm:w-auto">
            <div className="relative w-full sm:w-80">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-zinc-400" />
              <Input className="pl-9" placeholder="Search recent enrollments..." />
            </div>
            <Button variant="outline" size="icon"><Filter className="h-4 w-4" /></Button>
          </div>
        </div>

        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Public ID</TableHead>
              <TableHead>Display Name</TableHead>
              <TableHead>Country</TableHead>
              <TableHead>Route Type</TableHead>
              <TableHead>Enrolled</TableHead>
              <TableHead className="text-right">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {(!data?.recent_enrollments || data.recent_enrollments.length === 0) ? (
              <TableRow><TableCell colSpan={6} className="h-32 text-center"><div className="flex flex-col items-center gap-2 text-zinc-400"><Inbox className="h-8 w-8" /><p className="text-sm">No recent enrollments</p></div></TableCell></TableRow>
            ) : data.recent_enrollments.map((e) => (
              <TableRow key={e.profile_id}>
                <TableCell className="font-mono text-xs text-zinc-500">{e.public_id}</TableCell>
                <TableCell className="font-medium text-zinc-900">{e.display_name || "(Unnamed)"}</TableCell>
                <TableCell><Badge variant="outline">{e.country_code}</Badge></TableCell>
                <TableCell className="text-zinc-600">{e.route_type}</TableCell>
                <TableCell className="text-sm text-zinc-500">{new Date(e.enrolled_at).toLocaleDateString()}</TableCell>
                <TableCell className="text-right">
                  <DropdownMenu>
                    <DropdownMenuTrigger asChild><Button variant="ghost" size="icon"><MoreHorizontal className="h-4 w-4 text-zinc-400" /></Button></DropdownMenuTrigger>
                    <DropdownMenuContent align="end" className="w-48">
                      <DropdownMenuLabel>Actions</DropdownMenuLabel>
                      <DropdownMenuSeparator />
                      <DropdownMenuItem><Eye className="mr-2 h-4 w-4" /> View Profile</DropdownMenuItem>
                      <DropdownMenuItem><Activity className="mr-2 h-4 w-4" /> Match History</DropdownMenuItem>
                      <DropdownMenuSeparator />
                      <DropdownMenuItem className="text-amber-600"><RotateCcw className="mr-2 h-4 w-4" /> Reset Biometrics</DropdownMenuItem>
                      <DropdownMenuItem className="text-rose-600"><Ban className="mr-2 h-4 w-4" /> Revoke Access</DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </Card>
    </div>
  );
}
