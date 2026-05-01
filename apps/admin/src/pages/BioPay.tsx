import { Fingerprint, Activity, ShieldAlert, UserX, Loader2, RefreshCw, AlertTriangle, Inbox } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  DataTableEmptyRow,
  DataTablePagination,
  DataTableSearch,
  DataTableToolbar,
} from "@/components/ui/data-table-controls";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { useDataTableController } from "@/lib/data-table-controller";
import { useAsyncData } from "@/lib/hooks";
import { getBioPaySummary } from "@/lib/api/admin-operations";

const PAGE_SIZE = 20;

export function BioPay() {
  const table = useDataTableController({ pageSize: PAGE_SIZE });
  const { data, loading, error, refetch } = useAsyncData(getBioPaySummary);

  if (loading) {
    return <div className="flex h-96 items-center justify-center"><Loader2 className="h-8 w-8 animate-spin text-indigo-600" /></div>;
  }
  if (error) {
    return <div className="flex h-96 flex-col items-center justify-center gap-4"><AlertTriangle className="h-10 w-10 text-amber-500" /><p className="text-sm text-zinc-600">{error}</p><Button onClick={refetch} variant="outline" size="sm"><RefreshCw className="h-4 w-4 mr-2" /> Retry</Button></div>;
  }

  const matchRate = data && data.total_matches_24h > 0
    ? ((data.successful_matches_24h / data.total_matches_24h) * 100).toFixed(1)
    : "—";
  const recentEnrollments = data?.recent_enrollments ?? [];
  const normalizedSearch = table.search.trim().toLowerCase();
  const filteredEnrollments = normalizedSearch
    ? recentEnrollments.filter((enrollment) =>
        [
          enrollment.public_id,
          enrollment.display_name,
          enrollment.country_code,
          enrollment.route_type,
        ]
          .filter((value): value is string => typeof value === "string" && value.length > 0)
          .some((value) => value.toLowerCase().includes(normalizedSearch))
      )
    : recentEnrollments;
  const visibleEnrollments = table.paginate(filteredEnrollments);

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
            <div className="text-2xl font-bold text-zinc-900">{matchRate === "—" ? "—" : `${matchRate}%`}</div>
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
        <DataTableToolbar>
          <DataTableSearch
            placeholder="Search recent enrollments..."
            value={table.search}
            onChange={table.setSearch}
          />
        </DataTableToolbar>

        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Public ID</TableHead>
              <TableHead>Display Name</TableHead>
              <TableHead>Country</TableHead>
              <TableHead>Route Type</TableHead>
              <TableHead>Enrolled</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {filteredEnrollments.length === 0 ? (
              <DataTableEmptyRow
                colSpan={5}
                icon={<Inbox className="h-8 w-8" />}
                message="No recent enrollments"
              />
            ) : visibleEnrollments.map((e) => (
              <TableRow key={e.profile_id}>
                <TableCell className="font-mono text-xs text-zinc-500">{e.public_id}</TableCell>
                <TableCell className="font-medium text-zinc-900">{e.display_name || "(Unnamed)"}</TableCell>
                <TableCell><Badge variant="outline">{e.country_code}</Badge></TableCell>
                <TableCell className="text-zinc-600">{e.route_type}</TableCell>
                <TableCell className="text-sm text-zinc-500">{new Date(e.enrolled_at).toLocaleDateString()}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
        <DataTablePagination
          page={table.page}
          pageSize={table.pageSize}
          total={filteredEnrollments.length}
          onPageChange={table.setPage}
        />
      </Card>
    </div>
  );
}
