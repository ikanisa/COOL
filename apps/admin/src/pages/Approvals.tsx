import { Loader2, RefreshCw, AlertTriangle, Inbox, ShieldAlert, Clock, ThumbsUp } from "lucide-react";
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
import { getAuditStats, listAuditEntries } from "@/lib/api/admin-operations";

const PAGE_SIZE = 20;

export function Approvals() {
  const table = useDataTableController({ pageSize: PAGE_SIZE });
  const { data, loading, error, refetch } = useAsyncData(listAuditEntries);

  const { data: stats } = useAsyncData(getAuditStats);

  if (loading) {
    return <div className="flex h-96 items-center justify-center"><Loader2 className="h-8 w-8 animate-spin text-indigo-600" /></div>;
  }
  if (error) {
    return <div className="flex h-96 flex-col items-center justify-center gap-4"><AlertTriangle className="h-10 w-10 text-amber-500" /><p className="text-sm text-zinc-600">{error}</p><Button onClick={refetch} variant="outline" size="sm"><RefreshCw className="h-4 w-4 mr-2" /> Retry</Button></div>;
  }

  const entries = data ?? [];
  const normalizedSearch = table.search.trim().toLowerCase();
  const filteredEntries = normalizedSearch
    ? entries.filter((entry) =>
        [
          entry.actor_name,
          entry.actor_phone,
          entry.action,
          entry.target_table,
          entry.target_id,
          entry.notes,
        ]
          .filter((value): value is string => typeof value === "string" && value.length > 0)
          .some((value) => value.toLowerCase().includes(normalizedSearch))
      )
    : entries;
  const visibleEntries = table.paginate(filteredEntries);

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
        <DataTableToolbar>
          <DataTableSearch
            placeholder="Search audit log..."
            value={table.search}
            onChange={table.setSearch}
          />
        </DataTableToolbar>

        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Actor</TableHead>
              <TableHead>Phone</TableHead>
              <TableHead>Action</TableHead>
              <TableHead>Target</TableHead>
              <TableHead>Notes</TableHead>
              <TableHead>Time</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {filteredEntries.length === 0 ? (
              <DataTableEmptyRow
                colSpan={6}
                icon={<Inbox className="h-8 w-8" />}
                message="No audit entries found"
              />
            ) : visibleEntries.map((e) => (
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
              </TableRow>
            ))}
          </TableBody>
        </Table>
        <DataTablePagination
          page={table.page}
          pageSize={table.pageSize}
          total={filteredEntries.length}
          onPageChange={table.setPage}
        />
      </Card>
    </div>
  );
}
