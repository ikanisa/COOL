import { useEffect, useState } from "react";
import {
  Search,
  Filter,
  Download,
  MoreHorizontal,
  Plus,
  Eye,
  Edit,
  Banknote,
  ShieldAlert,
  Loader2,
  RefreshCw,
  Inbox,
  FileSpreadsheet,
  X,
} from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Table,
  TableBody,
  TableCell,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { SortableHeader, useSort } from "@/components/ui/sortable-header";
import { supabase } from "@/lib/supabase";
import { useAsyncData } from "@/lib/hooks";
import { exportToCSV, exportToTSV } from "@/lib/export";

interface LoanRow {
  [key: string]: unknown;
  id: string;
  member_id: string;
  group_id: string;
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

interface OptionRow {
  id: string;
  label: string;
  hint: string;
}

interface LoanDetail {
  loan: {
    id: string;
    loan_code: string;
    loan_type: string;
    initial_amount: number;
    total_paid: number;
    outstanding_balance: number;
    repayment_amount: number;
    repayment_frequency: string;
    status: string;
    issued_at: string;
    due_date: string | null;
    completed_at: string | null;
    notes: string | null;
    member_name: string;
    member_phone: string;
    group_name: string;
  };
  repayments: Array<{
    id: string;
    amount: number;
    method: string;
    reference: string | null;
    notes: string | null;
    recorded_by_name: string | null;
    created_at: string;
  }>;
}

const PAGE_SIZE = 20;
const STATUS_FILTERS = [
  { value: null, label: "All Loans" },
  { value: "active", label: "Active" },
  { value: "completed", label: "Completed" },
  { value: "non_performing", label: "Non-Performing" },
  { value: "defaulted", label: "Defaulted" },
];
const LOAN_TYPE_OPTIONS = [
  { value: "general", label: "General" },
  { value: "solar", label: "Solar" },
  { value: "insurance", label: "Insurance" },
  { value: "taxes", label: "Taxes" },
  { value: "emoto", label: "E-Moto" },
];
const FREQ_LABELS: Record<string, string> = {
  daily: "Daily",
  weekly: "Weekly",
  monthly: "Monthly",
};
const STATUS_VARIANT: Record<
  string,
  "success" | "danger" | "warning" | "default"
> = {
  active: "success",
  completed: "default",
  non_performing: "warning",
  defaulted: "danger",
};

export function Loans() {
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState<string | null>(null);
  const [page, setPage] = useState(0);
  const [editorOpen, setEditorOpen] = useState(false);
  const [detailLoanId, setDetailLoanId] = useState<string | null>(null);
  const [editingLoan, setEditingLoan] = useState<LoanRow | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [paymentLoan, setPaymentLoan] = useState<LoanRow | null>(null);
  const [paymentForm, setPaymentForm] = useState({
    amount: "",
    method: "cash",
    reference: "",
    notes: "",
  });
  const [editorForm, setEditorForm] = useState({
    memberId: "",
    groupId: "",
    loanType: "general",
    initialAmount: "",
    repaymentAmount: "",
    repaymentFrequency: "daily",
    dueDate: "",
    notes: "",
  });
  const { sortKey, sortDirection, handleSort, sortData } = useSort("issued_at");

  const {
    data: stats,
    refetch: refetchStats,
  } = useAsyncData(async () => {
    const { data, error } = await supabase.rpc("get_admin_loans_summary");
    if (error) throw new Error(error.message);
    return data as Record<string, number>;
  });

  const {
    data: data,
    loading,
    error,
    refetch,
  } = useAsyncData(async () => {
    let query = supabase
      .from("loans")
      .select(
        `
        id, member_id, group_id, loan_code, loan_type, initial_amount, total_paid,
        repayment_amount, repayment_frequency, status, issued_at, due_date, notes,
        users!loans_member_id_fkey ( full_name, phone ),
        groups!loans_group_id_fkey ( name )
      `,
        { count: "exact" },
      )
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
        member_id: r.member_id as string,
        group_id: r.group_id as string,
        loan_code: r.loan_code as string,
        loan_type: r.loan_type as string,
        initial_amount: Number(r.initial_amount ?? 0),
        total_paid: Number(r.total_paid ?? 0),
        balance: Number(r.initial_amount ?? 0) - Number(r.total_paid ?? 0),
        repayment_amount: Number(r.repayment_amount ?? 0),
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

  const { data: optionData } = useAsyncData(async () => {
    const [{ data: users, error: usersError }, { data: groups, error: groupsError }] =
      await Promise.all([
        supabase.from("users").select("id, full_name, phone").order("full_name"),
        supabase
          .from("groups")
          .select("id, name")
          .eq("type", "saving")
          .order("name"),
      ]);
    if (usersError) throw new Error(usersError.message);
    if (groupsError) throw new Error(groupsError.message);
    return {
      users: (users ?? []).map((row) => ({
        id: row.id as string,
        label: (row.full_name as string) || "(Unnamed)",
        hint: (row.phone as string) || "",
      })) as OptionRow[],
      groups: (groups ?? []).map((row) => ({
        id: row.id as string,
        label: row.name as string,
        hint: "",
      })) as OptionRow[],
    };
  });

  const {
    data: detailData,
    loading: detailLoading,
    refetch: refetchDetail,
  } = useAsyncData(async () => {
    if (!detailLoanId) {
      return null;
    }
    const { data, error } = await supabase.rpc("admin_get_loan_detail", {
      p_loan_id: detailLoanId,
    });
    if (error) throw new Error(error.message);
    return data as LoanDetail;
  }, [detailLoanId]);

  const loans = data?.rows ?? [];
  const total = data?.total ?? 0;
  const filtered = search.trim()
    ? loans.filter((l) =>
        l.member_name.toLowerCase().includes(search.toLowerCase()) ||
        l.group_name.toLowerCase().includes(search.toLowerCase()) ||
        l.loan_code.toLowerCase().includes(search.toLowerCase()),
      )
    : loans;
  const sorted = sortData(filtered);

  useEffect(() => {
    if (!editingLoan) {
      return;
    }
    setEditorForm({
      memberId: editingLoan.member_id,
      groupId: editingLoan.group_id,
      loanType: editingLoan.loan_type,
      initialAmount: String(editingLoan.initial_amount),
      repaymentAmount: String(editingLoan.repayment_amount),
      repaymentFrequency: editingLoan.repayment_frequency,
      dueDate: editingLoan.due_date?.slice(0, 10) ?? "",
      notes: editingLoan.notes ?? "",
    });
  }, [editingLoan]);

  const resetEditor = () => {
    setEditingLoan(null);
    setEditorForm({
      memberId: "",
      groupId: "",
      loanType: "general",
      initialAmount: "",
      repaymentAmount: "",
      repaymentFrequency: "daily",
      dueDate: "",
      notes: "",
    });
    setActionError(null);
    setEditorOpen(false);
  };

  const openCreate = () => {
    resetEditor();
    setEditorOpen(true);
  };

  const openEdit = (loan: LoanRow) => {
    setEditingLoan(loan);
    setEditorOpen(true);
    setActionError(null);
  };

  const openPayment = (loan: LoanRow) => {
    setPaymentLoan(loan);
    setPaymentForm({
      amount: String(loan.balance),
      method: "cash",
      reference: "",
      notes: "",
    });
    setActionError(null);
  };

  const closePayment = () => {
    setPaymentLoan(null);
    setPaymentForm({
      amount: "",
      method: "cash",
      reference: "",
      notes: "",
    });
    setActionError(null);
  };

  const refreshLoansState = async () => {
    await Promise.all([refetch(), refetchStats()]);
    if (detailLoanId) {
      await refetchDetail();
    }
  };

  const handleEditorSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editingLoan && (!editorForm.memberId || !editorForm.groupId)) {
      setActionError("Member and group are required.");
      return;
    }

    setSubmitting(true);
    setActionError(null);
    try {
      const params = editingLoan
        ? {
            p_loan_id: editingLoan.id,
            p_loan_type: editorForm.loanType,
            p_initial_amount: Number(editorForm.initialAmount),
            p_repayment_amount: Number(editorForm.repaymentAmount),
            p_repayment_frequency: editorForm.repaymentFrequency,
            p_due_date: editorForm.dueDate || null,
            p_notes: editorForm.notes.trim() || null,
          }
        : {
            p_member_id: editorForm.memberId,
            p_group_id: editorForm.groupId,
            p_loan_type: editorForm.loanType,
            p_initial_amount: Number(editorForm.initialAmount),
            p_repayment_amount: Number(editorForm.repaymentAmount),
            p_repayment_frequency: editorForm.repaymentFrequency,
            p_due_date: editorForm.dueDate || null,
            p_notes: editorForm.notes.trim() || null,
          };

      const { error } = await supabase.rpc(
        editingLoan ? "admin_update_loan" : "admin_create_loan",
        params,
      );
      if (error) throw new Error(error.message);
      await refreshLoansState();
      resetEditor();
    } catch (err) {
      setActionError(
        err instanceof Error
          ? err.message
          : "Failed to save loan changes.",
      );
    } finally {
      setSubmitting(false);
    }
  };

  const handlePaymentSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!paymentLoan) {
      return;
    }

    setSubmitting(true);
    setActionError(null);
    try {
      const { error } = await supabase.rpc("admin_record_loan_repayment", {
        p_loan_id: paymentLoan.id,
        p_amount: Number(paymentForm.amount),
        p_method: paymentForm.method,
        p_reference: paymentForm.reference.trim() || null,
        p_notes: paymentForm.notes.trim() || null,
      });
      if (error) throw new Error(error.message);
      await refreshLoansState();
      closePayment();
    } catch (err) {
      setActionError(
        err instanceof Error ? err.message : "Failed to record repayment.",
      );
    } finally {
      setSubmitting(false);
    }
  };

  const handleStatusUpdate = async (loanId: string, status: string) => {
    setSubmitting(true);
    setActionError(null);
    try {
      const { error } = await supabase.rpc("admin_update_loan_status", {
        p_loan_id: loanId,
        p_status: status,
      });
      if (error) throw new Error(error.message);
      await refreshLoansState();
    } catch (err) {
      setActionError(
        err instanceof Error ? err.message : "Failed to update loan status.",
      );
    } finally {
      setSubmitting(false);
    }
  };

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
    return (
      <div className="flex h-96 items-center justify-center">
        <Loader2 className="h-8 w-8 animate-spin text-indigo-600" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex h-96 flex-col items-center justify-center gap-4">
        <ShieldAlert className="h-10 w-10 text-amber-500" />
        <p className="text-sm text-zinc-600">{error}</p>
        <Button onClick={refetch} variant="outline" size="sm">
          <RefreshCw className="h-4 w-4 mr-2" /> Retry
        </Button>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-zinc-900">
            Loans Management
          </h1>
          <p className="text-sm text-zinc-500 mt-1">
            Manage member loans, repayments, balances, and recovery status.
          </p>
        </div>
        <div className="flex items-center gap-3">
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="outline">
                <Download className="h-4 w-4 mr-2" /> Export
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-44">
              <DropdownMenuItem onClick={handleExportCSV}>
                <Download className="mr-2 h-4 w-4" /> Export CSV
              </DropdownMenuItem>
              <DropdownMenuItem onClick={handleExportExcel}>
                <FileSpreadsheet className="mr-2 h-4 w-4" /> Export Excel
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
          <Button
            className="bg-indigo-600 hover:bg-indigo-700 text-white"
            onClick={openCreate}
          >
            <Plus className="h-4 w-4 mr-2" /> New Loan
          </Button>
        </div>
      </div>

      {actionError && (
        <Card className="border-rose-200 bg-rose-50/60">
          <CardContent className="py-4 text-sm font-medium text-rose-700">
            {actionError}
          </CardContent>
        </Card>
      )}

      {editorOpen && (
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0">
            <CardTitle>
              {editingLoan ? "Edit Loan" : "Create Loan"}
            </CardTitle>
            <Button variant="ghost" size="icon" onClick={resetEditor}>
              <X className="h-4 w-4" />
            </Button>
          </CardHeader>
          <CardContent>
            <form onSubmit={handleEditorSubmit} className="space-y-4">
              {!editingLoan && (
                <div className="grid gap-4 md:grid-cols-2">
                  <div className="space-y-2">
                    <label className="text-sm font-medium text-zinc-900">
                      Member
                    </label>
                    <select
                      value={editorForm.memberId}
                      onChange={(e) =>
                        setEditorForm((prev) => ({
                          ...prev,
                          memberId: e.target.value,
                        }))
                      }
                      className="w-full h-10 px-3 rounded-lg border border-zinc-200 bg-white text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
                    >
                      <option value="">Select member…</option>
                      {(optionData?.users ?? []).map((user) => (
                        <option key={user.id} value={user.id}>
                          {user.label} {user.hint ? `(${user.hint})` : ""}
                        </option>
                      ))}
                    </select>
                  </div>
                  <div className="space-y-2">
                    <label className="text-sm font-medium text-zinc-900">
                      Savings Group
                    </label>
                    <select
                      value={editorForm.groupId}
                      onChange={(e) =>
                        setEditorForm((prev) => ({
                          ...prev,
                          groupId: e.target.value,
                        }))
                      }
                      className="w-full h-10 px-3 rounded-lg border border-zinc-200 bg-white text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
                    >
                      <option value="">Select group…</option>
                      {(optionData?.groups ?? []).map((group) => (
                        <option key={group.id} value={group.id}>
                          {group.label}
                        </option>
                      ))}
                    </select>
                  </div>
                </div>
              )}

              <div className="grid gap-4 md:grid-cols-2">
                <div className="space-y-2">
                  <label className="text-sm font-medium text-zinc-900">
                    Loan Type
                  </label>
                  <select
                    value={editorForm.loanType}
                    onChange={(e) =>
                      setEditorForm((prev) => ({
                        ...prev,
                        loanType: e.target.value,
                      }))
                    }
                    className="w-full h-10 px-3 rounded-lg border border-zinc-200 bg-white text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
                  >
                    {LOAN_TYPE_OPTIONS.map((option) => (
                      <option key={option.value} value={option.value}>
                        {option.label}
                      </option>
                    ))}
                  </select>
                </div>
                <div className="space-y-2">
                  <label className="text-sm font-medium text-zinc-900">
                    Repayment Frequency
                  </label>
                  <select
                    value={editorForm.repaymentFrequency}
                    onChange={(e) =>
                      setEditorForm((prev) => ({
                        ...prev,
                        repaymentFrequency: e.target.value,
                      }))
                    }
                    className="w-full h-10 px-3 rounded-lg border border-zinc-200 bg-white text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
                  >
                    <option value="daily">Daily</option>
                    <option value="weekly">Weekly</option>
                    <option value="monthly">Monthly</option>
                  </select>
                </div>
              </div>

              <div className="grid gap-4 md:grid-cols-3">
                <div className="space-y-2">
                  <label className="text-sm font-medium text-zinc-900">
                    Initial Amount (RWF)
                  </label>
                  <Input
                    type="number"
                    min="1"
                    value={editorForm.initialAmount}
                    onChange={(e) =>
                      setEditorForm((prev) => ({
                        ...prev,
                        initialAmount: e.target.value,
                      }))
                    }
                  />
                </div>
                <div className="space-y-2">
                  <label className="text-sm font-medium text-zinc-900">
                    Repayment Amount (RWF)
                  </label>
                  <Input
                    type="number"
                    min="1"
                    value={editorForm.repaymentAmount}
                    onChange={(e) =>
                      setEditorForm((prev) => ({
                        ...prev,
                        repaymentAmount: e.target.value,
                      }))
                    }
                  />
                </div>
                <div className="space-y-2">
                  <label className="text-sm font-medium text-zinc-900">
                    Due Date
                  </label>
                  <Input
                    type="date"
                    value={editorForm.dueDate}
                    onChange={(e) =>
                      setEditorForm((prev) => ({
                        ...prev,
                        dueDate: e.target.value,
                      }))
                    }
                  />
                </div>
              </div>

              <div className="space-y-2">
                <label className="text-sm font-medium text-zinc-900">
                  Notes
                </label>
                <Input
                  value={editorForm.notes}
                  onChange={(e) =>
                    setEditorForm((prev) => ({
                      ...prev,
                      notes: e.target.value,
                    }))
                  }
                  placeholder="Optional loan notes..."
                />
              </div>

              <div className="flex justify-end gap-3">
                <Button type="button" variant="outline" onClick={resetEditor}>
                  Cancel
                </Button>
                <Button
                  type="submit"
                  disabled={submitting}
                  className="bg-indigo-600 hover:bg-indigo-700 text-white"
                >
                  {submitting ? (
                    <>
                      <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                      Saving…
                    </>
                  ) : (
                    <>
                      <SaveLoanIcon />
                      {editingLoan ? "Save Changes" : "Create Loan"}
                    </>
                  )}
                </Button>
              </div>
            </form>
          </CardContent>
        </Card>
      )}

      {paymentLoan && (
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0">
            <CardTitle>
              Record Payment for {paymentLoan.loan_code}
            </CardTitle>
            <Button variant="ghost" size="icon" onClick={closePayment}>
              <X className="h-4 w-4" />
            </Button>
          </CardHeader>
          <CardContent>
            <form onSubmit={handlePaymentSubmit} className="space-y-4">
              <div className="grid gap-4 md:grid-cols-3">
                <div className="space-y-2">
                  <label className="text-sm font-medium text-zinc-900">
                    Amount (RWF)
                  </label>
                  <Input
                    type="number"
                    min="1"
                    max={paymentLoan.balance}
                    value={paymentForm.amount}
                    onChange={(e) =>
                      setPaymentForm((prev) => ({
                        ...prev,
                        amount: e.target.value,
                      }))
                    }
                  />
                </div>
                <div className="space-y-2">
                  <label className="text-sm font-medium text-zinc-900">
                    Method
                  </label>
                  <select
                    value={paymentForm.method}
                    onChange={(e) =>
                      setPaymentForm((prev) => ({
                        ...prev,
                        method: e.target.value,
                      }))
                    }
                    className="w-full h-10 px-3 rounded-lg border border-zinc-200 bg-white text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
                  >
                    <option value="cash">Cash</option>
                    <option value="momo">MoMo</option>
                  </select>
                </div>
                <div className="space-y-2">
                  <label className="text-sm font-medium text-zinc-900">
                    Reference
                  </label>
                  <Input
                    value={paymentForm.reference}
                    onChange={(e) =>
                      setPaymentForm((prev) => ({
                        ...prev,
                        reference: e.target.value,
                      }))
                    }
                    placeholder="Optional reference"
                  />
                </div>
              </div>

              <div className="space-y-2">
                <label className="text-sm font-medium text-zinc-900">
                  Notes
                </label>
                <Input
                  value={paymentForm.notes}
                  onChange={(e) =>
                    setPaymentForm((prev) => ({
                      ...prev,
                      notes: e.target.value,
                    }))
                  }
                  placeholder="Optional repayment note..."
                />
              </div>

              <div className="flex justify-end gap-3">
                <Button type="button" variant="outline" onClick={closePayment}>
                  Cancel
                </Button>
                <Button
                  type="submit"
                  disabled={submitting}
                  className="bg-indigo-600 hover:bg-indigo-700 text-white"
                >
                  {submitting ? (
                    <>
                      <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                      Recording…
                    </>
                  ) : (
                    <>
                      <Banknote className="h-4 w-4 mr-2" />
                      Record Payment
                    </>
                  )}
                </Button>
              </div>
            </form>
          </CardContent>
        </Card>
      )}

      {detailLoanId && (
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0">
            <CardTitle>Loan Details</CardTitle>
            <Button
              variant="ghost"
              size="icon"
              onClick={() => setDetailLoanId(null)}
            >
              <X className="h-4 w-4" />
            </Button>
          </CardHeader>
          <CardContent className="space-y-4">
            {detailLoading || !detailData ? (
              <div className="flex items-center justify-center py-8">
                <Loader2 className="h-6 w-6 animate-spin text-zinc-400" />
              </div>
            ) : (
              <>
                <div className="grid gap-4 md:grid-cols-4">
                  <Metric label="Loan" value={detailData.loan.loan_code} />
                  <Metric
                    label="Member"
                    value={detailData.loan.member_name}
                    hint={detailData.loan.member_phone}
                  />
                  <Metric label="Group" value={detailData.loan.group_name} />
                  <Metric
                    label="Outstanding"
                    value={`${detailData.loan.outstanding_balance.toLocaleString()} RWF`}
                  />
                </div>

                <div className="grid gap-4 md:grid-cols-4">
                  <Metric
                    label="Initial"
                    value={`${detailData.loan.initial_amount.toLocaleString()} RWF`}
                  />
                  <Metric
                    label="Paid"
                    value={`${detailData.loan.total_paid.toLocaleString()} RWF`}
                  />
                  <Metric
                    label="Repayment"
                    value={`${detailData.loan.repayment_amount.toLocaleString()} ${FREQ_LABELS[detailData.loan.repayment_frequency] ?? detailData.loan.repayment_frequency}`}
                  />
                  <Metric
                    label="Status"
                    value={detailData.loan.status}
                    badge
                    badgeVariant={STATUS_VARIANT[detailData.loan.status] ?? "default"}
                  />
                </div>

                <div className="space-y-2">
                  <p className="text-sm font-medium text-zinc-900">
                    Repayment History
                  </p>
                  {detailData.repayments.length === 0 ? (
                    <p className="text-sm text-zinc-500">
                      No repayments recorded yet.
                    </p>
                  ) : (
                    <div className="space-y-2">
                      {detailData.repayments.map((repayment) => (
                        <div
                          key={repayment.id}
                          className="flex items-center justify-between rounded-lg border border-zinc-200 px-3 py-2"
                        >
                          <div>
                            <p className="text-sm font-medium text-zinc-900">
                              {repayment.amount.toLocaleString()} RWF via{" "}
                              {repayment.method}
                            </p>
                            <p className="text-xs text-zinc-500">
                              {new Date(repayment.created_at).toLocaleString()}
                              {repayment.recorded_by_name
                                ? ` • ${repayment.recorded_by_name}`
                                : ""}
                              {repayment.reference
                                ? ` • ${repayment.reference}`
                                : ""}
                            </p>
                          </div>
                          {repayment.notes && (
                            <span className="text-xs text-zinc-500">
                              {repayment.notes}
                            </span>
                          )}
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              </>
            )}
          </CardContent>
        </Card>
      )}

      {stats && (
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium text-zinc-500">
                Total Loans
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold text-zinc-900">
                {stats.total_loans ?? 0}
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium text-zinc-500">
                Active
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold text-emerald-600">
                {stats.active_loans ?? 0}
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium text-zinc-500">
                Outstanding Balance
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold text-indigo-600">
                {Number(stats.outstanding_balance ?? 0).toLocaleString()}{" "}
                <span className="text-xs font-normal text-zinc-400">RWF</span>
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium text-zinc-500">
                Defaulted
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold text-rose-600">
                {stats.defaulted_loans ?? 0}
              </div>
            </CardContent>
          </Card>
        </div>
      )}

      <Card>
        <div className="p-4 border-b border-zinc-100 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div className="flex items-center gap-2 w-full sm:w-auto">
            <div className="relative w-full sm:w-80">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-zinc-400" />
              <Input
                placeholder="Search member, group, or loan ID..."
                className="pl-9 bg-zinc-50 border-zinc-200"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
              />
            </div>
            <Button variant="outline" size="icon" className="shrink-0">
              <Filter className="h-4 w-4 text-zinc-500" />
            </Button>
          </div>
          <div className="flex items-center gap-2 overflow-x-auto pb-2 sm:pb-0">
            {STATUS_FILTERS.map((f) => (
              <Badge
                key={f.value ?? "all"}
                variant={statusFilter === f.value ? "secondary" : "outline"}
                className={
                  statusFilter === f.value
                    ? "bg-indigo-50 text-indigo-700 cursor-pointer whitespace-nowrap"
                    : "cursor-pointer hover:bg-zinc-50 whitespace-nowrap"
                }
                onClick={() => {
                  setStatusFilter(f.value);
                  setPage(0);
                }}
              >
                {f.label}
              </Badge>
            ))}
          </div>
        </div>
        <div className="px-4 py-2 bg-zinc-50/50 border-b border-zinc-100 text-xs font-medium text-zinc-500 flex justify-end">
          * All values in RWF
        </div>

        <Table>
          <TableHeader>
            <TableRow>
              <SortableHeader
                label="Loan ID"
                sortKey="loan_code"
                currentSort={sortKey}
                currentDirection={sortDirection}
                onSort={handleSort}
              />
              <SortableHeader
                label="Member"
                sortKey="member_name"
                currentSort={sortKey}
                currentDirection={sortDirection}
                onSort={handleSort}
              />
              <SortableHeader
                label="Group"
                sortKey="group_name"
                currentSort={sortKey}
                currentDirection={sortDirection}
                onSort={handleSort}
              />
              <SortableHeader
                label="Type"
                sortKey="loan_type"
                currentSort={sortKey}
                currentDirection={sortDirection}
                onSort={handleSort}
              />
              <SortableHeader
                label="Initial"
                sortKey="initial_amount"
                currentSort={sortKey}
                currentDirection={sortDirection}
                onSort={handleSort}
              />
              <SortableHeader
                label="Paid"
                sortKey="total_paid"
                currentSort={sortKey}
                currentDirection={sortDirection}
                onSort={handleSort}
              />
              <SortableHeader
                label="Balance"
                sortKey="balance"
                currentSort={sortKey}
                currentDirection={sortDirection}
                onSort={handleSort}
              />
              <SortableHeader
                label="Repayment"
                sortKey="repayment_amount"
                currentSort={sortKey}
                currentDirection={sortDirection}
                onSort={handleSort}
              />
              <SortableHeader
                label="Status"
                sortKey="status"
                currentSort={sortKey}
                currentDirection={sortDirection}
                onSort={handleSort}
              />
              <SortableHeader
                label="Issued"
                sortKey="issued_at"
                currentSort={sortKey}
                currentDirection={sortDirection}
                onSort={handleSort}
              />
              <SortableHeader
                label="Actions"
                sortKey=""
                currentSort={null}
                currentDirection={null}
                onSort={() => {}}
                className="text-right"
              />
            </TableRow>
          </TableHeader>
          <TableBody>
            {sorted.length === 0 ? (
              <TableRow>
                <TableCell colSpan={11} className="h-32 text-center">
                  <div className="flex flex-col items-center gap-2 text-zinc-400">
                    <Inbox className="h-8 w-8" />
                    <p className="text-sm">No loans found</p>
                  </div>
                </TableCell>
              </TableRow>
            ) : (
              sorted.map((loan) => (
                <TableRow key={loan.id}>
                  <TableCell className="font-mono text-xs text-zinc-500">
                    {loan.loan_code}
                  </TableCell>
                  <TableCell className="text-zinc-900 font-medium">
                    {loan.member_name}
                  </TableCell>
                  <TableCell className="text-zinc-600">
                    {loan.group_name}
                  </TableCell>
                  <TableCell>
                    <Badge variant="outline" className="bg-zinc-50 capitalize">
                      {loan.loan_type}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-zinc-900 font-medium">
                    {loan.initial_amount.toLocaleString()}
                  </TableCell>
                  <TableCell className="text-emerald-600 font-medium">
                    {loan.total_paid.toLocaleString()}
                  </TableCell>
                  <TableCell className="text-indigo-600 font-bold">
                    {loan.balance.toLocaleString()}
                  </TableCell>
                  <TableCell className="text-zinc-600">
                    <div className="flex flex-col">
                      <span className="font-medium">
                        {loan.repayment_amount.toLocaleString()}
                      </span>
                      <span className="text-[10px] text-zinc-400">
                        {FREQ_LABELS[loan.repayment_frequency] ??
                          loan.repayment_frequency}
                      </span>
                    </div>
                  </TableCell>
                  <TableCell>
                    <Badge
                      variant={STATUS_VARIANT[loan.status] ?? "default"}
                      className="capitalize"
                    >
                      {loan.status === "non_performing"
                        ? "Non-Performing"
                        : loan.status}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-sm text-zinc-500">
                    {new Date(loan.issued_at).toLocaleDateString()}
                  </TableCell>
                  <TableCell className="text-right">
                    <DropdownMenu>
                      <DropdownMenuTrigger asChild>
                        <Button variant="ghost" size="icon">
                          <MoreHorizontal className="h-4 w-4 text-zinc-400" />
                        </Button>
                      </DropdownMenuTrigger>
                      <DropdownMenuContent align="end" className="w-48">
                        <DropdownMenuLabel>Actions</DropdownMenuLabel>
                        <DropdownMenuSeparator />
                        <DropdownMenuItem
                          className="cursor-pointer"
                          onClick={() => setDetailLoanId(loan.id)}
                        >
                          <Eye className="mr-2 h-4 w-4" /> View Details
                        </DropdownMenuItem>
                        <DropdownMenuItem
                          className="cursor-pointer"
                          onClick={() => openPayment(loan)}
                        >
                          <Banknote className="mr-2 h-4 w-4" /> Record Payment
                        </DropdownMenuItem>
                        <DropdownMenuItem
                          className="cursor-pointer"
                          onClick={() => openEdit(loan)}
                        >
                          <Edit className="mr-2 h-4 w-4" /> Edit Loan
                        </DropdownMenuItem>
                        <DropdownMenuSeparator />
                        <DropdownMenuItem
                          className="cursor-pointer text-rose-600 focus:text-rose-600 focus:bg-rose-50"
                          onClick={() =>
                            handleStatusUpdate(loan.id, "defaulted")
                          }
                        >
                          <ShieldAlert className="mr-2 h-4 w-4" /> Mark as
                          Defaulted
                        </DropdownMenuItem>
                      </DropdownMenuContent>
                    </DropdownMenu>
                  </TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>

        <div className="flex items-center justify-between p-4 border-t border-zinc-100">
          <p className="text-sm text-zinc-500">
            Showing {total === 0 ? 0 : page * PAGE_SIZE + 1}–
            {Math.min((page + 1) * PAGE_SIZE, total)} of {total}
          </p>
          <div className="flex gap-2">
            <Button
              variant="outline"
              size="sm"
              disabled={page === 0}
              onClick={() => setPage(page - 1)}
            >
              Previous
            </Button>
            <Button
              variant="outline"
              size="sm"
              disabled={(page + 1) * PAGE_SIZE >= total}
              onClick={() => setPage(page + 1)}
            >
              Next
            </Button>
          </div>
        </div>
      </Card>
    </div>
  );
}

function SaveLoanIcon() {
  return <Edit className="h-4 w-4 mr-2" />;
}

function Metric(props: {
  label: string;
  value: string;
  hint?: string;
  badge?: boolean;
  badgeVariant?: "success" | "danger" | "warning" | "default";
}) {
  return (
    <div className="rounded-lg border border-zinc-200 p-3">
      <p className="text-xs font-medium uppercase tracking-wide text-zinc-500">
        {props.label}
      </p>
      {props.badge ? (
        <Badge
          variant={props.badgeVariant ?? "default"}
          className="mt-2 capitalize"
        >
          {props.value}
        </Badge>
      ) : (
        <p className="mt-2 text-sm font-semibold text-zinc-900">
          {props.value}
        </p>
      )}
      {props.hint && <p className="text-xs text-zinc-500 mt-1">{props.hint}</p>}
    </div>
  );
}
