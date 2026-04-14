import { useState } from "react";
import { Search, Filter, Download, MoreHorizontal, ArrowUpRight, ArrowDownLeft, Eye, RotateCcw, AlertTriangle as AlertTriangleIcon, Loader2, RefreshCw, Inbox, FileSpreadsheet } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { DetailSheet, DetailSection, DetailRow } from "@/components/ui/detail-sheet";
import { supabase } from "@/lib/supabase";
import { useAsyncData } from "@/lib/hooks";
import { exportToCSV, exportToTSV } from "@/lib/export";
import { toast } from "sonner";

interface ContributionRow {
  id: string;
  amount: number;
  status: string;
  momo_reference: string | null;
  created_at: string;
  user_name: string;
  user_phone: string;
  group_name: string;
}

interface LedgerRow {
  id: string;
  amount: number;
  currency: string;
  entry_type: string;
  ledger_scope: string;
  ledger_status: string;
  statement_label: string;
  counterparty_name: string | null;
  external_reference: string | null;
  tx_datetime: string;
  created_at: string;
  user_name: string;
  user_phone: string;
}

const PAGE_SIZE = 20;

// ════════════════════════════════════════════════════════════════════
// Contributions Tab (legacy group_contributions table)
// ════════════════════════════════════════════════════════════════════

function ContributionsTab() {
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState<string | null>(null);
  const [page, setPage] = useState(0);
  const [selectedTxn, setSelectedTxn] = useState<ContributionRow | null>(null);

  const { data, loading, error, refetch } = useAsyncData(async () => {
    let query = supabase
      .from("group_contributions")
      .select(`
        id, amount, status, momo_reference, created_at,
        users!group_contributions_user_id_fkey ( full_name, phone ),
        groups!group_contributions_group_id_fkey ( name )
      `, { count: "exact" })
      .order("created_at", { ascending: false })
      .range(page * PAGE_SIZE, (page + 1) * PAGE_SIZE - 1);

    if (statusFilter) {
      query = query.eq("status", statusFilter);
    }

    const { data: rows, error: queryError, count } = await query;
    if (queryError) throw new Error(queryError.message);

    const mapped: ContributionRow[] = (rows ?? []).map((r: Record<string, unknown>) => {
      const user = r.users as Record<string, string> | null;
      const group = r.groups as Record<string, string> | null;
      return {
        id: r.id as string,
        amount: r.amount as number,
        status: r.status as string,
        momo_reference: r.momo_reference as string | null,
        created_at: r.created_at as string,
        user_name: user?.full_name ?? "(Unknown)",
        user_phone: user?.phone ?? "",
        group_name: group?.name ?? "(Unknown)",
      };
    });

    return { rows: mapped, total: count ?? 0 };
  }, [page, statusFilter], { refreshIntervalMs: 15000 });

  const txns = data?.rows ?? [];
  const total = data?.total ?? 0;
  const filtered = search.trim()
    ? txns.filter(
        (t) =>
          t.user_name.toLowerCase().includes(search.toLowerCase()) ||
          t.group_name.toLowerCase().includes(search.toLowerCase()) ||
          (t.momo_reference?.toLowerCase() ?? "").includes(search.toLowerCase())
      )
    : txns;

  if (loading && !data) {
    return <div className="flex h-96 items-center justify-center"><Loader2 className="h-8 w-8 animate-spin text-indigo-600" /></div>;
  }
  if (error) {
    return <div className="flex h-96 flex-col items-center justify-center gap-4"><AlertTriangleIcon className="h-10 w-10 text-amber-500" /><p className="text-sm text-zinc-600">{error}</p><Button onClick={refetch} variant="outline" size="sm"><RefreshCw className="h-4 w-4 mr-2" /> Retry</Button></div>;
  }

  return (
    <>
      <Card>
        <div className="flex flex-col sm:flex-row items-center justify-between p-4 border-b border-zinc-100 gap-4">
          <div className="flex items-center gap-3 w-full sm:w-auto">
            <div className="relative w-full sm:w-80">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-zinc-400" />
              <Input className="pl-9" placeholder="Search by name, group, or ref..." value={search} onChange={(e) => setSearch(e.target.value)} />
            </div>
            <Button variant="outline" size="icon" onClick={() => toast.info("Advanced filters coming soon.")}><Filter className="h-4 w-4" /></Button>
          </div>
          <div className="flex items-center gap-2 overflow-x-auto">
            {[null, "confirmed", "pending", "failed"].map((s) => (
              <Badge key={s ?? "all"} variant={statusFilter === s ? "default" : "outline"} className={statusFilter === s ? "bg-zinc-900 text-white cursor-pointer" : "cursor-pointer hover:bg-zinc-50"} onClick={() => { setStatusFilter(s); setPage(0); }}>
                {s ? s.charAt(0).toUpperCase() + s.slice(1) : "All"}
              </Badge>
            ))}
          </div>
        </div>
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
            {filtered.length === 0 ? (
              <TableRow><TableCell colSpan={8} className="h-32 text-center"><div className="flex flex-col items-center gap-2 text-zinc-400"><Inbox className="h-8 w-8" /><p className="text-sm">No contributions found</p></div></TableCell></TableRow>
            ) : filtered.map((txn) => (
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
                    <DropdownMenuTrigger asChild><Button variant="ghost" size="icon"><MoreHorizontal className="h-4 w-4 text-zinc-400" /></Button></DropdownMenuTrigger>
                    <DropdownMenuContent align="end" className="w-48">
                      <DropdownMenuLabel>Actions</DropdownMenuLabel>
                      <DropdownMenuSeparator />
                      <DropdownMenuItem onClick={() => setSelectedTxn(txn)}><Eye className="mr-2 h-4 w-4" /> View Details</DropdownMenuItem>
                      <DropdownMenuItem onClick={() => toast.info("Download Receipt coming soon.")}><Download className="mr-2 h-4 w-4" /> Download Receipt</DropdownMenuItem>
                      <DropdownMenuSeparator />
                      <DropdownMenuItem onClick={() => toast.info("Refund coming soon.")} className="text-amber-600 focus:text-amber-600"><RotateCcw className="mr-2 h-4 w-4" /> Refund</DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>

        <div className="flex items-center justify-between p-4 border-t border-zinc-100">
          <p className="text-sm text-zinc-500">Showing {page * PAGE_SIZE + 1}–{Math.min((page + 1) * PAGE_SIZE, total)} of {total}</p>
          <div className="flex gap-2">
            <Button variant="outline" size="sm" disabled={page === 0} onClick={() => setPage(page - 1)}>Previous</Button>
            <Button variant="outline" size="sm" disabled={(page + 1) * PAGE_SIZE >= total} onClick={() => setPage(page + 1)}>Next</Button>
          </div>
        </div>
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
  const [search, setSearch] = useState("");
  const [scopeFilter, setScopeFilter] = useState<string | null>(null);
  const [page, setPage] = useState(0);
  const [selectedEntry, setSelectedEntry] = useState<LedgerRow | null>(null);

  const { data, loading, error, refetch } = useAsyncData(async () => {
    let query = supabase
      .from("momo_ledger_entries")
      .select(`
        id, amount, currency, entry_type, ledger_scope, ledger_status,
        statement_label, counterparty_name, external_reference,
        tx_datetime, created_at,
        users!momo_ledger_entries_user_id_fkey ( full_name, phone )
      `, { count: "exact" })
      .order("tx_datetime", { ascending: false })
      .range(page * PAGE_SIZE, (page + 1) * PAGE_SIZE - 1);

    if (scopeFilter) {
      query = query.eq("ledger_scope", scopeFilter);
    }

    const { data: rows, error: queryError, count } = await query;
    if (queryError) throw new Error(queryError.message);

    const mapped: LedgerRow[] = (rows ?? []).map((r: Record<string, unknown>) => {
      const user = r.users as Record<string, string> | null;
      return {
        id: r.id as string,
        amount: r.amount as number,
        currency: (r.currency as string) ?? "RWF",
        entry_type: (r.entry_type as string) ?? "",
        ledger_scope: (r.ledger_scope as string) ?? "",
        ledger_status: (r.ledger_status as string) ?? "",
        statement_label: (r.statement_label as string) ?? "",
        counterparty_name: r.counterparty_name as string | null,
        external_reference: r.external_reference as string | null,
        tx_datetime: (r.tx_datetime as string) ?? (r.created_at as string),
        created_at: r.created_at as string,
        user_name: user?.full_name ?? "(Unknown)",
        user_phone: user?.phone ?? "",
      };
    });

    return { rows: mapped, total: count ?? 0 };
  }, [page, scopeFilter], { refreshIntervalMs: 15000 });

  const entries = data?.rows ?? [];
  const total = data?.total ?? 0;
  const filtered = search.trim()
    ? entries.filter(
        (e) =>
          e.user_name.toLowerCase().includes(search.toLowerCase()) ||
          e.statement_label.toLowerCase().includes(search.toLowerCase()) ||
          (e.counterparty_name?.toLowerCase() ?? "").includes(search.toLowerCase()) ||
          (e.external_reference?.toLowerCase() ?? "").includes(search.toLowerCase())
      )
    : entries;

  if (loading && !data) {
    return <div className="flex h-96 items-center justify-center"><Loader2 className="h-8 w-8 animate-spin text-indigo-600" /></div>;
  }
  if (error) {
    return <div className="flex h-96 flex-col items-center justify-center gap-4"><AlertTriangleIcon className="h-10 w-10 text-amber-500" /><p className="text-sm text-zinc-600">{error}</p><Button onClick={refetch} variant="outline" size="sm"><RefreshCw className="h-4 w-4 mr-2" /> Retry</Button></div>;
  }

  return (
    <>
      <Card>
        <div className="flex flex-col sm:flex-row items-center justify-between p-4 border-b border-zinc-100 gap-4">
          <div className="flex items-center gap-3 w-full sm:w-auto">
            <div className="relative w-full sm:w-80">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-zinc-400" />
              <Input className="pl-9" placeholder="Search by name, label, or reference..." value={search} onChange={(e) => setSearch(e.target.value)} />
            </div>
          </div>
          <div className="flex items-center gap-2 overflow-x-auto">
            {[null, "group", "partner", "wallet"].map((s) => (
              <Badge key={s ?? "all"} variant={scopeFilter === s ? "default" : "outline"} className={scopeFilter === s ? "bg-zinc-900 text-white cursor-pointer" : "cursor-pointer hover:bg-zinc-50"} onClick={() => { setScopeFilter(s); setPage(0); }}>
                {s ? s.charAt(0).toUpperCase() + s.slice(1) : "All Scopes"}
              </Badge>
            ))}
          </div>
        </div>

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
            {filtered.length === 0 ? (
              <TableRow><TableCell colSpan={8} className="h-32 text-center"><div className="flex flex-col items-center gap-2 text-zinc-400"><Inbox className="h-8 w-8" /><p className="text-sm">No ledger entries found</p></div></TableCell></TableRow>
            ) : filtered.map((entry) => (
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

        <div className="flex items-center justify-between p-4 border-t border-zinc-100">
          <p className="text-sm text-zinc-500">Showing {Math.min(page * PAGE_SIZE + 1, total)}–{Math.min((page + 1) * PAGE_SIZE, total)} of {total}</p>
          <div className="flex gap-2">
            <Button variant="outline" size="sm" disabled={page === 0} onClick={() => setPage(page - 1)}>Previous</Button>
            <Button variant="outline" size="sm" disabled={(page + 1) * PAGE_SIZE >= total} onClick={() => setPage(page + 1)}>Next</Button>
          </div>
        </div>
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
