import { useState } from "react";
import {
  Search, Filter, Download, MoreHorizontal, Plus, Eye, Edit,
  Banknote, ShieldAlert, Loader2, RefreshCw, Inbox, FileSpreadsheet,
} from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem,
  DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Table, TableBody, TableCell, TableHeader, TableRow } from "@/components/ui/table";
import { SortableHeader, useSort } from "@/components/ui/sortable-header";
import { supabase } from "@/lib/supabase";
import { useAsyncData } from "@/lib/hooks";
import { exportToCSV, exportToTSV } from "@/lib/export";

interface LoanRow {
  [key: string]: unknown;
  id: string;
  loan_code: string;
  loan_type: string;
  initial_amount: number;
  total_paid: number;
  balance: number;
  repayment_amount: number;
  repayment_frequency: string;
  status: string;
  issued_at: string;
  due_date: string | null;
  notes: string | null;
  member_name: string;
  member_phone: string;
  group_name: string;
}

const PAGE_SIZE = 20;
const STATUS_FILTERS = [
  { value: null, label: "All Loans" },
  { value: "active", label: "Active" },
  { value: "completed", label: "Completed" },
  { value: "non_performing", label: "Non-Performing" },
  { value: "defaulted", label: "Defaulted" },
];
const FREQ_LABELS: Record<string, string> = { daily: "Daily", weekly: "Weekly", monthly: "Monthly" };
const STATUS_VARIANT: Record<string, "success" | "danger" | "warning" | "default"> = {
  active: "success",
  completed: "default",
  non_performing: "warning",
  defaulted: "danger",
};

export function Loans() {
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState<string | null>(null);
  const [page, setPage] = useState(0);
  const { sortKey, sortDirection, handleSort, sortData } = useSort("issued_at");

  // Summary stats
  const { data: stats } = useAsyncData(async () => {
    const { data, error } = await supabase.rpc("get_admin_loans_summary");
    if (error) throw new Error(error.message);
    return data as Record<string, number>;
  });

  // Loans list
  const { data, loading, error, refetch } = useAsyncData(async () => {
    let query = supabase
      .from("loans")
      .select(`
        id, loan_code, loan_type, initial_amount, total_paid,
        repayment_amount, repayment_frequency, status, issued_at, due_date, notes,
        users!loans_member_id_fkey ( full_name, phone ),
        groups!loans_group_id_fkey ( name )
      `, { count: "exact" })
      .order("issued_at", { ascending: false })
      .range(page * PAGE_SIZE, (page + 1) * PAGE_SIZE - 1);

    if (statusFilter) {
      query = query.eq("status", statusFilter);
    }

    const { data: rows, error: queryError, count } = await query;
    if (queryError) throw new Error(queryError.message);

    const mapped: LoanRow[] = (rows ?? []).map((r: Record<string, unknown>) => {
      const user = r.users as Record<string, string> | null;
      const group = r.groups as Record<string, string> | null;
      return {
        id: r.id as string,
        loan_code: r.loan_code as string,
        loan_type: r.loan_type as string,
        initial_amount: r.initial_amount as number,
        total_paid: r.total_paid as number,
        balance: (r.initial_amount as number) - (r.total_paid as number),
        repayment_amount: r.repayment_amount as number,
        repayment_frequency: r.repayment_frequency as string,
        status: r.status as string,
        issued_at: r.issued_at as string,
        due_date: r.due_date as string | null,
        notes: r.notes as string | null,
        member_name: user?.full_name ?? "(Unknown)",
        member_phone: user?.phone ?? "",
        group_name: group?.name ?? "(Unknown)",
      };
    });

    return { rows: mapped, total: count ?? 0 };
  }, [page, statusFilter]);

  const loans = data?.rows ?? [];
  const total = data?.total ?? 0;
  const filtered = search.trim()
    ? loans.filter((l) =>
        l.member_name.toLowerCase().includes(search.toLowerCase()) ||
        l.group_name.toLowerCase().includes(search.toLowerCase()) ||
        l.loan_code.toLowerCase().includes(search.toLowerCase())
      )
    : loans;
  const sorted = sortData(filtered);

  const handleExportCSV = () => {
    exportToCSV(sorted, "loans_export", [
      { key: "loan_code", label: "Loan ID" },
      { key: "member_name", label: "Member" },
      { key: "member_phone", label: "Phone" },
      { key: "group_name", label: "Group" },
      { key: "loan_type", label: "Type" },
      { key: "initial_amount", label: "Initial Amount (RWF)" },
      { key: "total_paid", label: "Paid (RWF)" },
      { key: "balance", label: "Balance (RWF)" },
      { key: "repayment_amount", label: "Repayment" },
      { key: "repayment_frequency", label: "Frequency" },
      { key: "status", label: "Status" },
      { key: "issued_at", label: "Issued Date" },
    ]);
  };

  const handleExportExcel = () => {
    exportToTSV(sorted, "loans_export", [
      { key: "loan_code", label: "Loan ID" },
      { key: "member_name", label: "Member" },
      { key: "member_phone", label: "Phone" },
      { key: "group_name", label: "Group" },
      { key: "loan_type", label: "Type" },
      { key: "initial_amount", label: "Initial Amount (RWF)" },
      { key: "total_paid", label: "Paid (RWF)" },
      { key: "balance", label: "Balance (RWF)" },
      { key: "repayment_amount", label: "Repayment" },
      { key: "repayment_frequency", label: "Frequency" },
      { key: "status", label: "Status" },
      { key: "issued_at", label: "Issued Date" },
    ]);
  };

  if (loading && !data) {
    return <div className="flex h-96 items-center justify-center"><Loader2 className="h-8 w-8 animate-spin text-indigo-600" /></div>;
  }

  if (error) {
    return (
      <div className="flex h-96 flex-col items-center justify-center gap-4">
        <ShieldAlert className="h-10 w-10 text-amber-500" />
        <p className="text-sm text-zinc-600">{error}</p>
        <Button onClick={refetch} variant="outline" size="sm"><RefreshCw className="h-4 w-4 mr-2" /> Retry</Button>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-zinc-900">Loans Management</h1>
          <p className="text-sm text-zinc-500 mt-1">Manage member loans, repayments, and balances.</p>
        </div>
        <div className="flex items-center gap-3">
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="outline"><Download className="h-4 w-4 mr-2" /> Export</Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-44">
              <DropdownMenuItem onClick={handleExportCSV}><Download className="mr-2 h-4 w-4" /> Export CSV</DropdownMenuItem>
              <DropdownMenuItem onClick={handleExportExcel}><FileSpreadsheet className="mr-2 h-4 w-4" /> Export Excel</DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
          <Button className="bg-indigo-600 hover:bg-indigo-700 text-white"><Plus className="h-4 w-4 mr-2" /> New Loan</Button>
        </div>
      </div>

      {/* Summary Cards */}
      {stats && (
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
          <Card><CardHeader className="pb-2"><CardTitle className="text-sm font-medium text-zinc-500">Total Loans</CardTitle></CardHeader><CardContent><div className="text-2xl font-bold text-zinc-900">{stats.total_loans ?? 0}</div></CardContent></Card>
          <Card><CardHeader className="pb-2"><CardTitle className="text-sm font-medium text-zinc-500">Active</CardTitle></CardHeader><CardContent><div className="text-2xl font-bold text-emerald-600">{stats.active_loans ?? 0}</div></CardContent></Card>
          <Card><CardHeader className="pb-2"><CardTitle className="text-sm font-medium text-zinc-500">Outstanding Balance</CardTitle></CardHeader><CardContent><div className="text-2xl font-bold text-indigo-600">{Number(stats.outstanding_balance ?? 0).toLocaleString()} <span className="text-xs font-normal text-zinc-400">RWF</span></div></CardContent></Card>
          <Card><CardHeader className="pb-2"><CardTitle className="text-sm font-medium text-zinc-500">Defaulted</CardTitle></CardHeader><CardContent><div className="text-2xl font-bold text-rose-600">{stats.defaulted_loans ?? 0}</div></CardContent></Card>
        </div>
      )}

      {/* Loans Table */}
      <Card>
        {/* Toolbar */}
        <div className="p-4 border-b border-zinc-100 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div className="flex items-center gap-2 w-full sm:w-auto">
            <div className="relative w-full sm:w-80">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-zinc-400" />
              <Input placeholder="Search member, group, or loan ID..." className="pl-9 bg-zinc-50 border-zinc-200" value={search} onChange={(e) => setSearch(e.target.value)} />
            </div>
            <Button variant="outline" size="icon" className="shrink-0"><Filter className="h-4 w-4 text-zinc-500" /></Button>
          </div>
          <div className="flex items-center gap-2 overflow-x-auto pb-2 sm:pb-0">
            {STATUS_FILTERS.map((f) => (
              <Badge
                key={f.value ?? "all"}
                variant={statusFilter === f.value ? "secondary" : "outline"}
                className={statusFilter === f.value ? "bg-indigo-50 text-indigo-700 cursor-pointer whitespace-nowrap" : "cursor-pointer hover:bg-zinc-50 whitespace-nowrap"}
                onClick={() => { setStatusFilter(f.value); setPage(0); }}
              >
                {f.label}
              </Badge>
            ))}
          </div>
        </div>
        <div className="px-4 py-2 bg-zinc-50/50 border-b border-zinc-100 text-xs font-medium text-zinc-500 flex justify-end">* All values in RWF</div>

        {/* Table */}
        <Table>
          <TableHeader>
            <TableRow>
              <SortableHeader label="Loan ID" sortKey="loan_code" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} />
              <SortableHeader label="Member" sortKey="member_name" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} />
              <SortableHeader label="Group" sortKey="group_name" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} />
              <SortableHeader label="Type" sortKey="loan_type" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} />
              <SortableHeader label="Initial" sortKey="initial_amount" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} />
              <SortableHeader label="Paid" sortKey="total_paid" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} />
              <SortableHeader label="Balance" sortKey="balance" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} />
              <SortableHeader label="Repayment" sortKey="repayment_amount" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} />
              <SortableHeader label="Status" sortKey="status" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} />
              <SortableHeader label="Issued" sortKey="issued_at" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} />
              <SortableHeader label="Actions" sortKey="" currentSort={null} currentDirection={null} onSort={() => {}} className="text-right" />
            </TableRow>
          </TableHeader>
          <TableBody>
            {sorted.length === 0 ? (
              <TableRow><TableCell colSpan={11} className="h-32 text-center"><div className="flex flex-col items-center gap-2 text-zinc-400"><Inbox className="h-8 w-8" /><p className="text-sm">No loans found</p></div></TableCell></TableRow>
            ) : sorted.map((loan) => (
              <TableRow key={loan.id}>
                <TableCell className="font-mono text-xs text-zinc-500">{loan.loan_code}</TableCell>
                <TableCell className="text-zinc-900 font-medium">{loan.member_name}</TableCell>
                <TableCell className="text-zinc-600">{loan.group_name}</TableCell>
                <TableCell><Badge variant="outline" className="bg-zinc-50 capitalize">{loan.loan_type}</Badge></TableCell>
                <TableCell className="text-zinc-900 font-medium">{loan.initial_amount.toLocaleString()}</TableCell>
                <TableCell className="text-emerald-600 font-medium">{loan.total_paid.toLocaleString()}</TableCell>
                <TableCell className="text-indigo-600 font-bold">{loan.balance.toLocaleString()}</TableCell>
                <TableCell className="text-zinc-600">
                  <div className="flex flex-col">
                    <span className="font-medium">{loan.repayment_amount.toLocaleString()}</span>
                    <span className="text-[10px] text-zinc-400">{FREQ_LABELS[loan.repayment_frequency] ?? loan.repayment_frequency}</span>
                  </div>
                </TableCell>
                <TableCell>
                  <Badge variant={STATUS_VARIANT[loan.status] ?? "default"} className="capitalize">
                    {loan.status === "non_performing" ? "Non-Performing" : loan.status}
                  </Badge>
                </TableCell>
                <TableCell className="text-sm text-zinc-500">{new Date(loan.issued_at).toLocaleDateString()}</TableCell>
                <TableCell className="text-right">
                  <DropdownMenu>
                    <DropdownMenuTrigger asChild><Button variant="ghost" size="icon"><MoreHorizontal className="h-4 w-4 text-zinc-400" /></Button></DropdownMenuTrigger>
                    <DropdownMenuContent align="end" className="w-48">
                      <DropdownMenuLabel>Actions</DropdownMenuLabel>
                      <DropdownMenuSeparator />
                      <DropdownMenuItem className="cursor-pointer"><Eye className="mr-2 h-4 w-4" /> View Details</DropdownMenuItem>
                      <DropdownMenuItem className="cursor-pointer"><Banknote className="mr-2 h-4 w-4" /> Record Payment</DropdownMenuItem>
                      <DropdownMenuItem className="cursor-pointer"><Edit className="mr-2 h-4 w-4" /> Edit Loan</DropdownMenuItem>
                      <DropdownMenuSeparator />
                      <DropdownMenuItem className="cursor-pointer text-rose-600 focus:text-rose-600 focus:bg-rose-50"><ShieldAlert className="mr-2 h-4 w-4" /> Mark as Defaulted</DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>

        {/* Pagination */}
        <div className="flex items-center justify-between p-4 border-t border-zinc-100">
          <p className="text-sm text-zinc-500">Showing {total === 0 ? 0 : page * PAGE_SIZE + 1}–{Math.min((page + 1) * PAGE_SIZE, total)} of {total}</p>
          <div className="flex gap-2">
            <Button variant="outline" size="sm" disabled={page === 0} onClick={() => setPage(page - 1)}>Previous</Button>
            <Button variant="outline" size="sm" disabled={(page + 1) * PAGE_SIZE >= total} onClick={() => setPage(page + 1)}>Next</Button>
          </div>
        </div>
      </Card>
    </div>
  );
}
