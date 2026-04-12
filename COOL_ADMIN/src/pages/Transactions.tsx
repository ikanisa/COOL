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
import { supabase } from "@/lib/supabase";
import { useAsyncData } from "@/lib/hooks";
import { exportToCSV, exportToTSV } from "@/lib/export";

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

const PAGE_SIZE = 20;

export function Transactions() {
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState<string | null>(null);
  const [page, setPage] = useState(0);

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
  }, [page, statusFilter]);

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
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-zinc-900">Contributions</h1>
          <p className="text-sm text-zinc-500 mt-1">{total} total records</p>
        </div>
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="outline"><Download className="h-4 w-4 mr-2" /> Export</Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-44">
            <DropdownMenuItem onClick={() => exportToCSV(filtered, 'contributions', [
              { key: 'user_name', label: 'Member' }, { key: 'user_phone', label: 'Phone' },
              { key: 'group_name', label: 'Group' }, { key: 'amount', label: 'Amount (RWF)' },
              { key: 'momo_reference', label: 'Reference' }, { key: 'status', label: 'Status' },
              { key: 'created_at', label: 'Date' },
            ])}><Download className="mr-2 h-4 w-4" /> Export CSV</DropdownMenuItem>
            <DropdownMenuItem onClick={() => exportToTSV(filtered, 'contributions', [
              { key: 'user_name', label: 'Member' }, { key: 'user_phone', label: 'Phone' },
              { key: 'group_name', label: 'Group' }, { key: 'amount', label: 'Amount (RWF)' },
              { key: 'momo_reference', label: 'Reference' }, { key: 'status', label: 'Status' },
              { key: 'created_at', label: 'Date' },
            ])}><FileSpreadsheet className="mr-2 h-4 w-4" /> Export Excel</DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>

      <Card>
        <div className="flex flex-col sm:flex-row items-center justify-between p-4 border-b border-zinc-100 gap-4">
          <div className="flex items-center gap-3 w-full sm:w-auto">
            <div className="relative w-full sm:w-80">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-zinc-400" />
              <Input className="pl-9" placeholder="Search by name, group, or ref..." value={search} onChange={(e) => setSearch(e.target.value)} />
            </div>
            <Button variant="outline" size="icon"><Filter className="h-4 w-4" /></Button>
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
              <TableRow><TableCell colSpan={8} className="h-32 text-center"><div className="flex flex-col items-center gap-2 text-zinc-400"><Inbox className="h-8 w-8" /><p className="text-sm">No transactions found</p></div></TableCell></TableRow>
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
                      <DropdownMenuItem><Eye className="mr-2 h-4 w-4" /> View Details</DropdownMenuItem>
                      <DropdownMenuItem><Download className="mr-2 h-4 w-4" /> Download Receipt</DropdownMenuItem>
                      <DropdownMenuSeparator />
                      <DropdownMenuItem className="text-amber-600 focus:text-amber-600"><RotateCcw className="mr-2 h-4 w-4" /> Refund</DropdownMenuItem>
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
    </div>
  );
}
