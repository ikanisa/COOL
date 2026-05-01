import {
  Activity,
  AlertTriangle as AlertTriangleIcon,
  CheckCircle,
  RefreshCw,
  Server,
  ShieldCheck,
  Smartphone,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  DataTableEmptyRow,
  DataTablePagination,
  DataTableSearch,
} from "@/components/ui/data-table-controls";
import { PageLoading } from "@/components/ui/states";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { useDataTableController } from "@/lib/data-table-controller";
import { getHealthStats, listHealthEvents, type HealthEvent } from "@/lib/api/admin-operations";
import { useAsyncData } from "@/lib/hooks";

const PAGE_SIZE = 20;

function statusVariant(severity: string): "success" | "warning" | "danger" | "outline" {
  if (severity === "error" || severity === "critical") return "danger";
  if (severity === "warning") return "warning";
  if (severity === "info" || severity === "ok" || severity === "healthy") return "success";
  return "outline";
}

function eventMatches(event: HealthEvent, query: string): boolean {
  const normalized = query.trim().toLowerCase();
  if (!normalized) return true;
  return [
    event.severity,
    event.service,
    event.component,
    event.message,
    JSON.stringify(event.metadata ?? {}),
  ].some((value) => value.toLowerCase().includes(normalized));
}

function latestSmsEvent(events: HealthEvent[]): HealthEvent | undefined {
  return events.find((event) =>
    [event.service, event.component, event.message]
      .join(" ")
      .toLowerCase()
      .match(/sms|momo|mobile money|m-money/)
  );
}

export function Health() {
  const table = useDataTableController({ pageSize: PAGE_SIZE });
  const { data: events, loading, error, refetch } = useAsyncData(listHealthEvents);
  const { data: stats } = useAsyncData(getHealthStats);

  if (loading) {
    return <PageLoading message="Loading operational health..." />;
  }

  const eventRows = events ?? [];
  const filteredEvents = eventRows.filter((event) => eventMatches(event, table.search));
  const visibleEvents = table.paginate(filteredEvents);
  const serviceCount = new Set(eventRows.map((event) => event.service).filter(Boolean)).size;
  const componentCount = new Set(eventRows.map((event) => event.component).filter(Boolean)).size;
  const smsEvent = latestSmsEvent(eventRows);
  const hasWarnings = (stats?.warnings ?? 0) > 0;

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-zinc-900">System Health</h1>
          <p className="mt-1 text-sm text-zinc-500">
            Operational events from the production health log. No synthetic status values.
          </p>
        </div>
        <Button onClick={refetch} variant="outline" size="sm">
          <RefreshCw className="mr-2 h-4 w-4" />
          Refresh
        </Button>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-semibold text-zinc-500">System Status</CardTitle>
            <ShieldCheck className={hasWarnings ? "h-4 w-4 text-amber-500" : "h-4 w-4 text-emerald-500"} />
          </CardHeader>
          <CardContent>
            <div className={hasWarnings ? "text-2xl font-bold text-amber-700" : "text-2xl font-bold text-emerald-700"}>
              {hasWarnings ? "Needs review" : "No warnings"}
            </div>
            <p className="mt-1 text-xs text-zinc-500">{stats?.warnings ?? 0} warning/error events in 24h</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-semibold text-zinc-500">Events (24h)</CardTitle>
            <Activity className="h-4 w-4 text-zinc-400" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-zinc-900">{stats?.last24h ?? 0}</div>
            <p className="mt-1 text-xs text-zinc-500">{stats?.total ?? 0} total health events</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-semibold text-zinc-500">Observed Services</CardTitle>
            <Server className="h-4 w-4 text-zinc-400" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-zinc-900">{serviceCount}</div>
            <p className="mt-1 text-xs text-zinc-500">{componentCount} components in recent events</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-semibold text-zinc-500">SMS Pipeline</CardTitle>
            <Smartphone className="h-4 w-4 text-zinc-400" />
          </CardHeader>
          <CardContent>
            {smsEvent ? (
              <>
                <Badge variant={statusVariant(smsEvent.severity)}>{smsEvent.severity}</Badge>
                <p className="mt-2 truncate text-xs text-zinc-500">{smsEvent.message}</p>
              </>
            ) : (
              <>
                <div className="text-2xl font-bold text-zinc-900">No signal</div>
                <p className="mt-1 text-xs text-zinc-500">No recent SMS/MoMo health event</p>
              </>
            )}
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader className="gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <CardTitle>Recent Operational Events</CardTitle>
            <p className="mt-1 text-sm text-zinc-500">
              Showing {filteredEvents.length} of {eventRows.length} latest records.
            </p>
          </div>
          <DataTableSearch
            placeholder="Search service, component, severity..."
            value={table.search}
            onChange={table.setSearch}
          />
        </CardHeader>
        <CardContent className="p-0">
          {error ? (
            <div className="py-8 text-center">
              <AlertTriangleIcon className="mx-auto mb-2 h-6 w-6 text-amber-500" />
              <p className="text-sm text-zinc-600">{error}</p>
            </div>
          ) : filteredEvents.length === 0 ? (
            <Table>
              <TableBody>
                <DataTableEmptyRow
                  colSpan={5}
                  icon={<CheckCircle className="h-8 w-8" />}
                  message="No operational events match this filter"
                />
              </TableBody>
            </Table>
          ) : (
            <>
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
                  {visibleEvents.map((event) => (
                    <TableRow key={event.id}>
                      <TableCell>
                        <Badge variant={statusVariant(event.severity)}>{event.severity}</Badge>
                      </TableCell>
                      <TableCell className="font-medium text-zinc-900">{event.service ?? "—"}</TableCell>
                      <TableCell className="text-zinc-600">{event.component ?? "—"}</TableCell>
                      <TableCell className="max-w-[360px] truncate text-sm text-zinc-600">
                        {event.message}
                      </TableCell>
                      <TableCell className="text-sm text-zinc-500">
                        {new Date(event.created_at).toLocaleString()}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
              <DataTablePagination
                page={table.page}
                pageSize={table.pageSize}
                total={filteredEvents.length}
                onPageChange={table.setPage}
              />
            </>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
