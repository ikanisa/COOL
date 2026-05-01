import { useState } from "react";
import {
  Download, MoreHorizontal, Plus, Eye,
  ShieldAlert, Loader2, RefreshCw, Inbox, FileSpreadsheet,
} from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem,
  DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  DataTableEmptyRow,
  DataTableFilterChips,
  DataTablePagination,
  DataTableSearch,
  DataTableToolbar,
  type DataTableFilterOption,
} from "@/components/ui/data-table-controls";
import { Table, TableBody, TableCell, TableHeader, TableRow } from "@/components/ui/table";
import { SortableHeader } from "@/components/ui/sortable-header";
import { DetailSheet, DetailSection, DetailRow } from "@/components/ui/detail-sheet";
import { CreateLoanSheet } from "@/components/loans/CreateLoanSheet";
import { useDataTableController } from "@/lib/data-table-controller";
import { useAsyncData } from "@/lib/hooks";
import { exportToCSV, exportToTSV } from "@/lib/export";
import {
  getAdminLoansSummary,
  listAdminLoans,
  type AdminLoanRow,
} from "@/lib/api/admin-loans";

const PAGE_SIZE = 20;
const STATUS_FILTERS: Array<DataTableFilterOption<string | null>> = [
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
  const table = useDataTableController<string | null>({
    pageSize: PAGE_SIZE,
    initialSortKey: "issued_at",
    initialSortDirection: "desc",
  });
  const [selectedLoan, setSelectedLoan] = useState<AdminLoanRow | null>(null);
  const [showCreate, setShowCreate] = useState(false);

  // Summary stats
  const { data: stats } = useAsyncData(getAdminLoansSummary);

  // Loans list
  const { data, loading, error, refetch } = useAsyncData(
    () =>
      listAdminLoans({
        page: table.page,
        pageSize: table.pageSize,
        status: table.filter,
        search: table.search,
      }),
    [table.page, table.pageSize, table.filter, table.search]
  );

  const loans = data?.rows ?? [];
  const total = data?.total ?? 0;
  const sorted = table.sortData(loans);

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
          <Button onClick={() => setShowCreate(true)} className="bg-indigo-600 hover:bg-indigo-700 text-white"><Plus className="h-4 w-4 mr-2" /> New Loan</Button>
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
        <DataTableToolbar
          trailing={
            <DataTableFilterChips
              value={table.filter}
              options={STATUS_FILTERS}
              onChange={table.setFilter}
            />
          }
        >
          <DataTableSearch
            placeholder="Search member, group, or loan ID..."
            value={table.search}
            onChange={table.setSearch}
          />
        </DataTableToolbar>
        <div className="px-4 py-2 bg-zinc-50/50 border-b border-zinc-100 text-xs font-medium text-zinc-500 flex justify-end">* All values in RWF</div>

        {/* Table */}
        <Table>
          <TableHeader>
            <TableRow>
              <SortableHeader label="Loan ID" sortKey="loan_code" currentSort={table.sortKey} currentDirection={table.sortDirection} onSort={table.handleSort} />
              <SortableHeader label="Member" sortKey="member_name" currentSort={table.sortKey} currentDirection={table.sortDirection} onSort={table.handleSort} />
              <SortableHeader label="Group" sortKey="group_name" currentSort={table.sortKey} currentDirection={table.sortDirection} onSort={table.handleSort} className="hidden md:table-cell" />
              <SortableHeader label="Type" sortKey="loan_type" currentSort={table.sortKey} currentDirection={table.sortDirection} onSort={table.handleSort} className="hidden lg:table-cell" />
              <SortableHeader label="Initial" sortKey="initial_amount" currentSort={table.sortKey} currentDirection={table.sortDirection} onSort={table.handleSort} className="hidden sm:table-cell" />
              <SortableHeader label="Paid" sortKey="total_paid" currentSort={table.sortKey} currentDirection={table.sortDirection} onSort={table.handleSort} className="hidden lg:table-cell" />
              <SortableHeader label="Balance" sortKey="balance" currentSort={table.sortKey} currentDirection={table.sortDirection} onSort={table.handleSort} />
              <SortableHeader label="Repayment" sortKey="repayment_amount" currentSort={table.sortKey} currentDirection={table.sortDirection} onSort={table.handleSort} className="hidden xl:table-cell" />
              <SortableHeader label="Status" sortKey="status" currentSort={table.sortKey} currentDirection={table.sortDirection} onSort={table.handleSort} />
              <SortableHeader label="Issued" sortKey="issued_at" currentSort={table.sortKey} currentDirection={table.sortDirection} onSort={table.handleSort} className="hidden md:table-cell" />
              <SortableHeader label="Actions" sortKey="" currentSort={null} currentDirection={null} onSort={() => {}} className="text-right" />
            </TableRow>
          </TableHeader>
          <TableBody>
            {sorted.length === 0 ? (
              <DataTableEmptyRow
                colSpan={11}
                icon={<Inbox className="h-8 w-8" />}
                message="No loans found"
              />
            ) : sorted.map((loan) => (
              <TableRow key={loan.id}>
                <TableCell className="font-mono text-xs text-zinc-500">{loan.loan_code}</TableCell>
                <TableCell className="text-zinc-900 font-medium">{loan.member_name}</TableCell>
                <TableCell className="text-zinc-600 hidden md:table-cell">{loan.group_name}</TableCell>
                <TableCell className="hidden lg:table-cell"><Badge variant="outline" className="bg-zinc-50 capitalize">{loan.loan_type}</Badge></TableCell>
                <TableCell className="text-zinc-900 font-medium hidden sm:table-cell">{loan.initial_amount.toLocaleString()}</TableCell>
                <TableCell className="text-emerald-600 font-medium hidden lg:table-cell">{loan.total_paid.toLocaleString()}</TableCell>
                <TableCell className="text-indigo-600 font-bold">{loan.balance.toLocaleString()}</TableCell>
                <TableCell className="text-zinc-600 hidden xl:table-cell">
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
                <TableCell className="text-sm text-zinc-500 hidden md:table-cell">{new Date(loan.issued_at).toLocaleDateString()}</TableCell>
                <TableCell className="text-right">
                  <DropdownMenu>
                    <DropdownMenuTrigger asChild><Button variant="ghost" size="icon" aria-label={`Open actions for loan ${loan.loan_code}`}><MoreHorizontal className="h-4 w-4 text-zinc-400" /></Button></DropdownMenuTrigger>
                    <DropdownMenuContent align="end" className="w-48">
                      <DropdownMenuLabel>Actions</DropdownMenuLabel>
                      <DropdownMenuSeparator />
                      <DropdownMenuItem className="cursor-pointer" onClick={() => setSelectedLoan(loan)}><Eye className="mr-2 h-4 w-4" /> View Details</DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>

        {/* Pagination */}
        <DataTablePagination
          page={table.page}
          pageSize={table.pageSize}
          total={total}
          onPageChange={table.setPage}
        />
      </Card>
      {/* Detail Sheet */}
      <DetailSheet
        open={!!selectedLoan}
        onClose={() => setSelectedLoan(null)}
        title={`Loan ${selectedLoan?.loan_code || ""}`}
        subtitle={selectedLoan?.member_name}
      >
        {selectedLoan && (
          <>
            <DetailSection title="Financials">
              <DetailRow label="Initial Amount" value={`${selectedLoan.initial_amount.toLocaleString()} RWF`} />
              <DetailRow label="Total Paid" value={`${selectedLoan.total_paid.toLocaleString()} RWF`} />
              <DetailRow label="Outstanding Balance" value={`${selectedLoan.balance.toLocaleString()} RWF`} />
              <DetailRow label="Repayment" value={`${selectedLoan.repayment_amount.toLocaleString()} RWF / ${FREQ_LABELS[selectedLoan.repayment_frequency] ?? selectedLoan.repayment_frequency}`} />
            </DetailSection>
            <DetailSection title="Loan Details">
              <DetailRow label="Loan Code" value={selectedLoan.loan_code} mono />
              <DetailRow label="Type" value={<Badge variant="outline" className="capitalize">{selectedLoan.loan_type}</Badge>} />
              <DetailRow label="Status" value={
                <Badge variant={STATUS_VARIANT[selectedLoan.status] ?? "default"} className="capitalize">
                  {selectedLoan.status === "non_performing" ? "Non-Performing" : selectedLoan.status}
                </Badge>
              } />
              <DetailRow label="Issued" value={new Date(selectedLoan.issued_at).toLocaleString()} />
              <DetailRow label="Due Date" value={selectedLoan.due_date ? new Date(selectedLoan.due_date).toLocaleString() : null} />
              <DetailRow label="Notes" value={selectedLoan.notes} />
            </DetailSection>
            <DetailSection title="Member & Group">
              <DetailRow label="Member" value={selectedLoan.member_name} />
              <DetailRow label="Phone" value={selectedLoan.member_phone} mono />
              <DetailRow label="Group" value={selectedLoan.group_name} />
              <DetailRow label="Loan ID" value={selectedLoan.id} mono />
            </DetailSection>
          </>
        )}
      </DetailSheet>

      {/* Create Loan Sheet */}
      <CreateLoanSheet
        open={showCreate}
        onClose={() => setShowCreate(false)}
        onCreated={() => { refetch(); }}
      />
    </div>
  );
}
