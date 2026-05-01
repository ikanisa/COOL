import { useState } from "react";
import { MoreHorizontal, ArrowUpRight, ArrowDownLeft, Eye, AlertTriangle as AlertTriangleIcon, Loader2, RefreshCw, Inbox } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  DataTableEmptyRow,
  DataTableFilterChips,
  DataTablePagination,
  DataTableSearch,
  DataTableToolbar,
  type DataTableFilterOption,
} from "@/components/ui/data-table-controls";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { DetailSheet, DetailSection, DetailRow } from "@/components/ui/detail-sheet";
import { useDataTableController } from "@/lib/data-table-controller";
import { useAsyncData } from "@/lib/hooks";
import {
  listContributionTransactions,
  listLedgerTransactions,
  type ContributionRow,
  type LedgerRow,
} from "@/lib/api/admin-transactions";

const PAGE_SIZE = 20;
const CONTRIBUTION_STATUS_FILTERS: Array<DataTableFilterOption<string | null>> = [
  { value: null, label: "All" },
  { value: "confirmed", label: "Confirmed" },
  { value: "pending", label: "Pending" },
  { value: "failed", label: "Failed" },
];
const LEDGER_SCOPE_FILTERS: Array<DataTableFilterOption<string | null>> = [
  { value: null, label: "All Scopes" },
  { value: "group", label: "Group" },
  { value: "partner", label: "Partner" },
  { value: "wallet", label: "Wallet" },
];

// ════════════════════════════════════════════════════════════════════
// Contributions Tab (legacy group_contributions table)
// ════════════════════════════════════════════════════════════════════

function ContributionsTab() {
  const table = useDataTableController<string | null>({ pageSize: PAGE_SIZE });
  const [selectedTxn, setSelectedTxn] = useState<ContributionRow | null>(null);

  const { data, loading, error, refetch } = useAsyncData(
    () =>
      listContributionTransactions({
        page: table.page,
        pageSize: table.pageSize,
        status: table.filter,
        search: table.search,
      }),
    [table.page, table.pageSize, table.filter, table.search],
    { refreshIntervalMs: 15000 }
  );

  const txns = data?.rows ?? [];
  const total = data?.total ?? 0;

  if (loading && !data) {
    return <div className="flex h-96 items-center justify-center"><Loader2 className="h-8 w-8 animate-spin text-indigo-600" /></div>;
  }
  if (error) {
    return <div className="flex h-96 flex-col items-center justify-center gap-4"><AlertTriangleIcon className="h-10 w-10 text-amber-500" /><p className="text-sm text-zinc-600">{error}</p><Button onClick={refetch} variant="outline" size="sm"><RefreshCw className="h-4 w-4 mr-2" /> Retry</Button></div>;
  }

  return (
    <>
      <Card>
        <DataTableToolbar
          trailing={
            <DataTableFilterChips
              value={table.filter}
              options={CONTRIBUTION_STATUS_FILTERS}
              onChange={table.setFilter}
            />
          }
        >
          <DataTableSearch
            placeholder="Search by name, group, or ref..."
            value={table.search}
            onChange={table.setSearch}
          />
        </DataTableToolbar>
        <div className="px-4 py-2 bg-zinc-50/50 border-b border-zinc-100 text-xs font-medium text-zinc-500 flex justify-end">* All values in RWF</div>

        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Member</TableHead>
              <TableHead>Phone</TableHead>
              <TableHead>Group</TableHead>
              <TableHead>Amount</TableHead>
              <TableHead>Reference</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Date</TableHead>
              <TableHead className="text-right">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {txns.length === 0 ? (
              <DataTableEmptyRow
                colSpan={8}
                icon={<Inbox className="h-8 w-8" />}
                message="No contributions found"
              />
            ) : txns.map((txn) => (
              <TableRow key={txn.id}>
                <TableCell className="font-medium text-zinc-900">{txn.user_name}</TableCell>
                <TableCell className="font-mono text-xs text-zinc-600">{txn.user_phone}</TableCell>
                <TableCell className="text-zinc-600">{txn.group_name}</TableCell>
                <TableCell>
                  <div className="flex items-center gap-1.5 font-medium text-zinc-900">
                    <ArrowUpRight className="h-3.5 w-3.5 text-emerald-500" />
                    {txn.amount.toLocaleString()}
                  </div>
                </TableCell>
                <TableCell className="font-mono text-xs text-zinc-500">{txn.momo_reference ?? "—"}</TableCell>
                <TableCell>
                  <Badge variant={txn.status === "confirmed" ? "success" : txn.status === "failed" ? "danger" : "warning"}>
                    {txn.status}
                  </Badge>
                </TableCell>
                <TableCell className="text-sm text-zinc-500">{new Date(txn.created_at).toLocaleDateString()}</TableCell>
                <TableCell className="text-right">
                  <DropdownMenu>
                    <DropdownMenuTrigger asChild><Button variant="ghost" size="icon" aria-label={`Open actions for transaction ${txn.id}`}><MoreHorizontal className="h-4 w-4 text-zinc-400" /></Button></DropdownMenuTrigger>
                    <DropdownMenuContent align="end" className="w-48">
                      <DropdownMenuLabel>Actions</DropdownMenuLabel>
                      <DropdownMenuSeparator />
                      <DropdownMenuItem onClick={() => setSelectedTxn(txn)}><Eye className="mr-2 h-4 w-4" /> View Details</DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>

        <DataTablePagination
          page={table.page}
          pageSize={table.pageSize}
          total={total}
          onPageChange={table.setPage}
        />
      </Card>
      {/* Detail Sheet */}
      <DetailSheet
        open={!!selectedTxn}
        onClose={() => setSelectedTxn(null)}
        title={`Contribution — ${selectedTxn?.amount.toLocaleString()} RWF`}
        subtitle={selectedTxn?.user_name}
      >
        {selectedTxn && (
          <>
            <DetailSection title="Transaction">
              <DetailRow label="Amount" value={`${selectedTxn.amount.toLocaleString()} RWF`} />
              <DetailRow label="Status" value={
                <Badge variant={selectedTxn.status === "confirmed" ? "success" : selectedTxn.status === "failed" ? "danger" : "warning"}>
                  {selectedTxn.status}
                </Badge>
              } />
              <DetailRow label="MoMo Reference" value={selectedTxn.momo_reference} mono />
              <DetailRow label="Date" value={new Date(selectedTxn.created_at).toLocaleString()} />
            </DetailSection>
            <DetailSection title="Member & Group">
              <DetailRow label="Member" value={selectedTxn.user_name} />
              <DetailRow label="Phone" value={selectedTxn.user_phone} mono />
              <DetailRow label="Group" value={selectedTxn.group_name} />
              <DetailRow label="Transaction ID" value={selectedTxn.id} mono />
            </DetailSection>
          </>
        )}
      </DetailSheet>
    </>
  );
}

// ════════════════════════════════════════════════════════════════════
// Ledger Entries Tab (momo_ledger_entries from SMS pipeline)
// ════════════════════════════════════════════════════════════════════

function LedgerEntriesTab() {
  const table = useDataTableController<string | null>({ pageSize: PAGE_SIZE });
  const [selectedEntry, setSelectedEntry] = useState<LedgerRow | null>(null);

  const { data, loading, error, refetch } = useAsyncData(
    () =>
      listLedgerTransactions({
        page: table.page,
        pageSize: table.pageSize,
        scope: table.filter,
        search: table.search,
      }),
    [table.page, table.pageSize, table.filter, table.search],
    { refreshIntervalMs: 15000 }
  );

  const entries = data?.rows ?? [];
  const total = data?.total ?? 0;

  if (loading && !data) {
    return <div className="flex h-96 items-center justify-center"><Loader2 className="h-8 w-8 animate-spin text-indigo-600" /></div>;
  }
  if (error) {
    return <div className="flex h-96 flex-col items-center justify-center gap-4"><AlertTriangleIcon className="h-10 w-10 text-amber-500" /><p className="text-sm text-zinc-600">{error}</p><Button onClick={refetch} variant="outline" size="sm"><RefreshCw className="h-4 w-4 mr-2" /> Retry</Button></div>;
  }

  return (
    <>
      <Card>
        <DataTableToolbar
          trailing={
            <DataTableFilterChips
              value={table.filter}
              options={LEDGER_SCOPE_FILTERS}
              onChange={table.setFilter}
            />
          }
        >
          <DataTableSearch
            placeholder="Search by name, label, or reference..."
            value={table.search}
            onChange={table.setSearch}
          />
        </DataTableToolbar>

        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>User</TableHead>
              <TableHead>Label</TableHead>
              <TableHead>Amount</TableHead>
              <TableHead>Scope</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Reference</TableHead>
              <TableHead>Date</TableHead>
              <TableHead className="text-right">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {entries.length === 0 ? (
              <DataTableEmptyRow
                colSpan={8}
                icon={<Inbox className="h-8 w-8" />}
                message="No ledger entries found"
              />
            ) : entries.map((entry) => (
              <TableRow key={entry.id}>
                <TableCell>
                  <div>
                    <p className="font-medium text-zinc-900">{entry.user_name}</p>
                    <p className="text-xs text-zinc-500 font-mono">{entry.user_phone}</p>
                  </div>
                </TableCell>
                <TableCell>
                  <div>
                    <p className="text-sm text-zinc-900 truncate max-w-[200px]">{entry.statement_label}</p>
                    {entry.counterparty_name && <p className="text-xs text-zinc-500">{entry.counterparty_name}</p>}
                  </div>
                </TableCell>
                <TableCell>
                  <div className="flex items-center gap-1.5 font-medium text-zinc-900">
                    {entry.entry_type === "credit" ? (
                      <ArrowDownLeft className="h-3.5 w-3.5 text-emerald-500" />
                    ) : (
                      <ArrowUpRight className="h-3.5 w-3.5 text-red-500" />
                    )}
                    {entry.amount.toLocaleString()} {entry.currency}
                  </div>
                </TableCell>
                <TableCell>
                  <Badge variant="outline" className="text-xs">
                    {entry.ledger_scope}
                  </Badge>
                </TableCell>
                <TableCell>
                  <Badge variant={entry.ledger_status === "posted" ? "success" : entry.ledger_status === "voided" ? "danger" : "warning"}>
                    {entry.ledger_status}
                  </Badge>
                </TableCell>
                <TableCell className="font-mono text-xs text-zinc-500 truncate max-w-[120px]">{entry.external_reference ?? "—"}</TableCell>
                <TableCell className="text-sm text-zinc-500">{new Date(entry.tx_datetime).toLocaleDateString()}</TableCell>
                <TableCell className="text-right">
                  <Button variant="ghost" size="icon" onClick={() => setSelectedEntry(entry)}>
                    <Eye className="h-4 w-4 text-zinc-400" />
                  </Button>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>

        <DataTablePagination
          page={table.page}
          pageSize={table.pageSize}
          total={total}
          onPageChange={table.setPage}
        />
      </Card>
      {/* Detail Sheet */}
      <DetailSheet
        open={!!selectedEntry}
        onClose={() => setSelectedEntry(null)}
        title={`Ledger — ${selectedEntry?.amount.toLocaleString()} ${selectedEntry?.currency ?? "RWF"}`}
        subtitle={selectedEntry?.user_name}
      >
        {selectedEntry && (
          <>
            <DetailSection title="Entry Details">
              <DetailRow label="Amount" value={`${selectedEntry.amount.toLocaleString()} ${selectedEntry.currency}`} />
              <DetailRow label="Type" value={selectedEntry.entry_type} />
              <DetailRow label="Scope" value={selectedEntry.ledger_scope} />
              <DetailRow label="Status" value={
                <Badge variant={selectedEntry.ledger_status === "posted" ? "success" : selectedEntry.ledger_status === "voided" ? "danger" : "warning"}>
                  {selectedEntry.ledger_status}
                </Badge>
              } />
              <DetailRow label="Label" value={selectedEntry.statement_label} />
              <DetailRow label="Counterparty" value={selectedEntry.counterparty_name ?? "—"} />
              <DetailRow label="Reference" value={selectedEntry.external_reference} mono />
            </DetailSection>
            <DetailSection title="User & Timing">
              <DetailRow label="User" value={selectedEntry.user_name} />
              <DetailRow label="Phone" value={selectedEntry.user_phone} mono />
              <DetailRow label="Transaction Date" value={new Date(selectedEntry.tx_datetime).toLocaleString()} />
              <DetailRow label="Created" value={new Date(selectedEntry.created_at).toLocaleString()} />
              <DetailRow label="Entry ID" value={selectedEntry.id} mono />
            </DetailSection>
          </>
        )}
      </DetailSheet>
    </>
  );
}

// ════════════════════════════════════════════════════════════════════
// Main Transactions Page (tabbed)
// ════════════════════════════════════════════════════════════════════

export function Transactions() {
  const [tab, setTab] = useState<"contributions" | "ledger">("contributions");

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-zinc-900">Transactions</h1>
          <p className="text-sm text-zinc-500 mt-1">Group contributions and SMS-parsed ledger entries</p>
        </div>
        <div className="flex items-center gap-2">
          <Badge
            variant={tab === "contributions" ? "default" : "outline"}
            className={tab === "contributions" ? "bg-indigo-600 text-white cursor-pointer" : "cursor-pointer hover:bg-zinc-50"}
            onClick={() => setTab("contributions")}
          >
            Contributions
          </Badge>
          <Badge
            variant={tab === "ledger" ? "default" : "outline"}
            className={tab === "ledger" ? "bg-indigo-600 text-white cursor-pointer" : "cursor-pointer hover:bg-zinc-50"}
            onClick={() => setTab("ledger")}
          >
            Ledger Entries
          </Badge>
        </div>
      </div>

      {tab === "contributions" ? <ContributionsTab /> : <LedgerEntriesTab />}
    </div>
  );
}
