import { useState } from "react";
import {
  Search,
  Filter,
  Download,
  MoreHorizontal,
  ArrowUpRight,
  Eye,
  AlertTriangle as AlertTriangleIcon,
  Loader2,
  RefreshCw,
  Inbox,
  FileSpreadsheet,
  ShieldAlert,
  Link2,
  CheckCircle2,
  XCircle,
} from "lucide-react";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
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
import { useAuth } from "@/lib/auth";

interface ContributionRow {
  id: string;
  group_id: string | null;
  user_id: string | null;
  amount: number;
  status: string;
  momo_reference: string | null;
  created_at: string;
  user_name: string;
  user_phone: string | null;
  group_name: string;
}

interface ManualReviewRow {
  review_id: string;
  group_id: string | null;
  group_name: string | null;
  payer_user_id: string | null;
  payer_name: string;
  amount: number;
  currency: string | null;
  reason: string;
  match_status: string;
  matched_reference: string | null;
  provider: string | null;
  payee_digits: string | null;
  sms_preview: string | null;
  created_at: string;
  updated_at: string;
}

interface GroupOption {
  id: string;
  name: string;
}

interface GroupMemberOption {
  user_id: string;
  display_name: string;
  phone: string | null;
}

interface GroupLedgerRow {
  ledger_id: string;
  payer_user_id: string | null;
  payer_name: string;
  payer_phone: string | null;
  amount: number;
  currency: string | null;
  tx_datetime: string;
  external_reference: string | null;
  tx_category: string | null;
  cashflow_bucket: string | null;
  statement_label: string | null;
  counterparty_name: string | null;
  target_table: string | null;
  target_record_id: string | null;
}

const PAGE_SIZE = 20;

function triggerTextDownload(filename: string, content: string) {
  const blob = new Blob([content], { type: "text/plain;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  document.body.appendChild(anchor);
  anchor.click();
  document.body.removeChild(anchor);
  URL.revokeObjectURL(url);
}

function formatDateTime(value: string | null) {
  if (!value) {
    return "—";
  }

  return new Date(value).toLocaleString();
}

function isAllocatedLedgerEntry(entry: GroupLedgerRow) {
  return entry.target_table === "group_contributions";
}

export function Transactions() {
  const { adminAccess } = useAuth();
  const hasPlatformAccess = Boolean(adminAccess?.has_platform_access);
  const bankPartnerId = adminAccess?.bank_partner_ids[0] ?? null;
  const isBankScopedWorkspace = !hasPlatformAccess && Boolean(bankPartnerId);

  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState<string | null>(null);
  const [page, setPage] = useState(0);
  const [selectedContributionId, setSelectedContributionId] = useState<string | null>(null);
  const [selectedReviewId, setSelectedReviewId] = useState<string | null>(null);
  const [selectedGroupId, setSelectedGroupId] = useState("");
  const [selectedMemberUserId, setSelectedMemberUserId] = useState("");
  const [allocationNote, setAllocationNote] = useState("");
  const [selectedLedgerId, setSelectedLedgerId] = useState<string | null>(null);
  const [selectedLedgerMemberUserId, setSelectedLedgerMemberUserId] = useState("");
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [actionSuccess, setActionSuccess] = useState<string | null>(null);

  const {
    data: contributionData,
    loading: contributionsLoading,
    error: contributionsError,
    refetch: refetchContributions,
  } = useAsyncData(async () => {
    if (!adminAccess) {
      return { rows: [] as ContributionRow[], total: 0 };
    }

    if (hasPlatformAccess) {
      let query = supabase
        .from("group_contributions")
        .select(
          `
            id, group_id, user_id, amount, status, momo_reference, created_at,
            users!group_contributions_user_id_fkey ( full_name, phone ),
            groups!group_contributions_group_id_fkey ( name )
          `,
          { count: "exact" },
        )
        .order("created_at", { ascending: false })
        .range(page * PAGE_SIZE, (page + 1) * PAGE_SIZE - 1);

      if (statusFilter) {
        query = query.eq("status", statusFilter);
      }

      const { data: rows, error: queryError, count } = await query;
      if (queryError) {
        throw new Error(queryError.message);
      }

      const mapped: ContributionRow[] = (rows ?? []).map((row: Record<string, unknown>) => {
        const user = row.users as Record<string, string> | null;
        const group = row.groups as Record<string, string> | null;

        return {
          id: row.id as string,
          group_id: (row.group_id as string | null) ?? null,
          user_id: (row.user_id as string | null) ?? null,
          amount: row.amount as number,
          status: row.status as string,
          momo_reference: (row.momo_reference as string | null) ?? null,
          created_at: row.created_at as string,
          user_name: user?.full_name ?? "(Unknown)",
          user_phone: user?.phone ?? null,
          group_name: group?.name ?? "(Unknown)",
        };
      });

      return { rows: mapped, total: count ?? 0 };
    }

    if (bankPartnerId) {
      const { data: rows, error: queryError } = await supabase.rpc(
        "get_bank_custody_contributions",
        {
          p_partner_id: bankPartnerId,
          p_group_id: null,
          p_status: statusFilter,
          p_limit: PAGE_SIZE,
          p_offset: page * PAGE_SIZE,
        },
      );

      if (queryError) {
        throw new Error(queryError.message);
      }

      const mapped: ContributionRow[] = (rows ?? []).map((row: Record<string, unknown>) => ({
        id: row.contribution_id as string,
        group_id: (row.group_id as string | null) ?? null,
        user_id: (row.user_id as string | null) ?? null,
        amount: row.amount as number,
        status: row.status as string,
        momo_reference: (row.momo_reference as string | null) ?? null,
        created_at: row.created_at as string,
        user_name: (row.contributor_name as string | null) ?? "Member",
        user_phone: null,
        group_name: (row.group_name as string | null) ?? "(Unknown)",
      }));

      return {
        rows: mapped,
        total:
          rows && rows.length > 0
            ? Number((rows[0] as Record<string, unknown>).total_count ?? rows.length)
            : 0,
      };
    }

    return { rows: [] as ContributionRow[], total: 0 };
  }, [adminAccess, hasPlatformAccess, bankPartnerId, page, statusFilter]);

  const {
    data: manualReviewData,
    loading: manualReviewsLoading,
    error: manualReviewsError,
    refetch: refetchManualReviews,
  } = useAsyncData(async () => {
    if (!adminAccess) {
      return [] as ManualReviewRow[];
    }

    if (isBankScopedWorkspace && bankPartnerId) {
      const { data: rows, error } = await supabase.rpc(
        "get_bank_manual_review_allocations",
        {
          p_partner_id: bankPartnerId,
          p_limit: 50,
          p_offset: 0,
        },
      );

      if (error) {
        throw new Error(error.message);
      }

      return (rows ?? []).map((row: Record<string, unknown>) => ({
        review_id: row.review_id as string,
        group_id: (row.group_id as string | null) ?? null,
        group_name: (row.group_name as string | null) ?? null,
        payer_user_id: (row.payer_user_id as string | null) ?? null,
        payer_name: (row.payer_name as string | null) ?? "Member",
        amount: row.amount as number,
        currency: "RWF",
        reason: (row.reason as string | null) ?? "manual_review",
        match_status: (row.match_status as string | null) ?? "manual_review",
        matched_reference: (row.matched_reference as string | null) ?? null,
        provider: (row.provider as string | null) ?? null,
        payee_digits: (row.payee_digits as string | null) ?? null,
        sms_preview: null,
        created_at: row.created_at as string,
        updated_at: row.updated_at as string,
      })) satisfies ManualReviewRow[];
    }

    const { data: rows, error } = await supabase.rpc(
      "get_momo_sms_manual_review_queue",
      {
        p_limit: 50,
        p_offset: 0,
      },
    );

    if (error) {
      throw new Error(error.message);
    }

    return (rows ?? []).map((row: Record<string, unknown>) => ({
      review_id: row.review_id as string,
      group_id: null,
      group_name: null,
      payer_user_id: (row.user_id as string | null) ?? null,
      payer_name:
        (row.payer_name as string | null) ??
        (row.payee_name as string | null) ??
        (row.sender as string | null) ??
        "Unknown payer",
      amount: Number(row.amount ?? 0),
      currency: (row.currency as string | null) ?? "RWF",
      reason: (row.reason as string | null) ?? "manual_review",
      match_status: (row.review_kind as string | null) ?? "manual_review",
      matched_reference: (row.momo_tx_id as string | null) ?? null,
      provider: (row.sender as string | null) ?? null,
      payee_digits:
        (row.payee_number_or_code as string | null) ??
        (row.merchant_code as string | null) ??
        null,
      sms_preview: (row.sms_preview as string | null) ?? null,
      created_at: row.review_created_at as string,
      updated_at: row.updated_at as string,
    })) satisfies ManualReviewRow[];
  }, [adminAccess, bankPartnerId, isBankScopedWorkspace]);

  const {
    data: groupOptions,
    loading: groupsLoading,
    error: groupsError,
    refetch: refetchGroups,
  } = useAsyncData(async () => {
    if (!adminAccess) {
      return [] as GroupOption[];
    }

    if (hasPlatformAccess) {
      const { data: rows, error } = await supabase
        .from("groups")
        .select("id, name")
        .eq("type", "saving")
        .order("name", { ascending: true });

      if (error) {
        throw new Error(error.message);
      }

      return (rows ?? []) as GroupOption[];
    }

    if (bankPartnerId) {
      const { data: rows, error } = await supabase.rpc(
        "get_bank_custody_groups",
        {
          p_partner_id: bankPartnerId,
          p_search: null,
          p_limit: 200,
          p_offset: 0,
        },
      );

      if (error) {
        throw new Error(error.message);
      }

      return (rows ?? [])
        .filter((row: Record<string, unknown>) => row.type === "saving")
        .map((row: Record<string, unknown>) => ({
          id: row.id as string,
          name: row.name as string,
        })) satisfies GroupOption[];
    }

    return [] as GroupOption[];
  }, [adminAccess, hasPlatformAccess, bankPartnerId]);

  const {
    data: groupMembers,
    loading: membersLoading,
    error: membersError,
    refetch: refetchMembers,
  } = useAsyncData(async () => {
    if (!selectedGroupId) {
      return [] as GroupMemberOption[];
    }

    if (isBankScopedWorkspace && bankPartnerId) {
      const { data: rows, error } = await supabase.rpc(
        "get_bank_custody_group_members",
        {
          p_partner_id: bankPartnerId,
          p_group_id: selectedGroupId,
          p_search: null,
          p_limit: 200,
          p_offset: 0,
        },
      );

      if (error) {
        throw new Error(error.message);
      }

      return (rows ?? []).map((row: Record<string, unknown>) => ({
        user_id: row.user_id as string,
        display_name: (row.display_name as string | null) ?? "Member",
        phone: null,
      })) satisfies GroupMemberOption[];
    }

    const { data: rows, error } = await supabase
      .from("group_members")
      .select(`
        user_id,
        display_name,
        users!group_members_user_id_fkey ( full_name, phone, public_user_id )
      `)
      .eq("group_id", selectedGroupId)
      .order("joined_at", { ascending: true });

    if (error) {
      throw new Error(error.message);
    }

    return (rows ?? []).map((row: Record<string, unknown>) => {
      const user = row.users as Record<string, string> | null;
      return {
        user_id: row.user_id as string,
        display_name:
          (row.display_name as string | null) ??
          user?.public_user_id ??
          user?.full_name ??
          "Member",
        phone: user?.phone ?? null,
      };
    }) satisfies GroupMemberOption[];
  }, [selectedGroupId, isBankScopedWorkspace, bankPartnerId]);

  const {
    data: groupLedgerEntries,
    loading: ledgerLoading,
    error: ledgerError,
    refetch: refetchLedgerEntries,
  } = useAsyncData(async () => {
    if (!selectedGroupId) {
      return [] as GroupLedgerRow[];
    }

    const { data: rows, error } = await supabase.rpc(
      "get_group_payment_ledger_entries",
      {
        p_group_id: selectedGroupId,
        p_start_at: null,
        p_end_before: null,
        p_payer_user_id: null,
        p_limit: 50,
        p_offset: 0,
      },
    );

    if (error) {
      throw new Error(error.message);
    }

    return (rows ?? []).map((row: Record<string, unknown>) => ({
      ledger_id: row.ledger_id as string,
      payer_user_id: (row.payer_user_id as string | null) ?? null,
      payer_name: (row.payer_name as string | null) ?? "Member",
      payer_phone: (row.payer_phone as string | null) ?? null,
      amount: Number(row.amount ?? 0),
      currency: (row.currency as string | null) ?? "RWF",
      tx_datetime: row.tx_datetime as string,
      external_reference: (row.external_reference as string | null) ?? null,
      tx_category: (row.tx_category as string | null) ?? null,
      cashflow_bucket: (row.cashflow_bucket as string | null) ?? null,
      statement_label: (row.statement_label as string | null) ?? null,
      counterparty_name: (row.counterparty_name as string | null) ?? null,
      target_table: (row.target_table as string | null) ?? null,
      target_record_id: (row.target_record_id as string | null) ?? null,
    })) satisfies GroupLedgerRow[];
  }, [selectedGroupId]);

  const contributions = contributionData?.rows ?? [];
  const total = contributionData?.total ?? 0;
  const manualReviews = manualReviewData ?? [];
  const selectedContribution =
    contributions.find((row: ContributionRow) => row.id === selectedContributionId) ?? null;
  const selectedReview =
    manualReviews.find((row: ManualReviewRow) => row.review_id === selectedReviewId) ?? null;
  const selectedLedgerEntry =
    (groupLedgerEntries ?? []).find((row: GroupLedgerRow) => row.ledger_id === selectedLedgerId) ?? null;
  const selectedGroupName =
    groupOptions?.find((group: GroupOption) => group.id === selectedGroupId)?.name ?? "Selected group";

  const filtered = search.trim()
    ? contributions.filter(
        (t) =>
          t.user_name.toLowerCase().includes(search.toLowerCase()) ||
          t.group_name.toLowerCase().includes(search.toLowerCase()) ||
          (t.momo_reference?.toLowerCase() ?? "").includes(search.toLowerCase()),
      )
    : contributions;

  const filteredManualReviews = search.trim()
    ? manualReviews.filter((review: ManualReviewRow) => {
        const query = search.toLowerCase();
        return (
          review.payer_name.toLowerCase().includes(query) ||
          (review.group_name?.toLowerCase().includes(query) ?? false) ||
          (review.reason.toLowerCase().includes(query) ?? false) ||
          (review.matched_reference?.toLowerCase().includes(query) ?? false)
        );
      })
    : manualReviews;

  const handleContributionReceiptDownload = (row: ContributionRow) => {
    const receipt = [
      "COOL APP CONTRIBUTION RECEIPT",
      `Contribution ID: ${row.id}`,
      `Group: ${row.group_name}`,
      `Member: ${row.user_name}`,
      `Phone: ${row.user_phone ?? "—"}`,
      `Amount (RWF): ${row.amount.toLocaleString()}`,
      `Status: ${row.status}`,
      `MoMo Reference: ${row.momo_reference ?? "—"}`,
      `Created At: ${formatDateTime(row.created_at)}`,
    ].join("\n");

    triggerTextDownload(`contribution-${row.id}.txt`, receipt);
  };

  const handlePrepareReview = (review: ManualReviewRow) => {
    setSelectedReviewId(review.review_id);
    if (review.group_id) {
      setSelectedGroupId(review.group_id);
      setSelectedLedgerId(null);
      setSelectedLedgerMemberUserId("");
    }
    setSelectedMemberUserId("");
    setAllocationNote("");
    setActionError(null);
    setActionSuccess(null);
  };

  const refreshTransactionWorkspaces = async () => {
    await Promise.all([
      refetchContributions(),
      refetchManualReviews(),
      refetchGroups(),
      selectedGroupId ? refetchMembers() : Promise.resolve(),
      selectedGroupId ? refetchLedgerEntries() : Promise.resolve(),
    ]);
  };

  const handleAllocateReview = async () => {
    if (!selectedReview) {
      setActionError("Select a manual-review row first.");
      return;
    }

    if (!selectedGroupId || !selectedMemberUserId) {
      setActionError("Choose a target group and member before allocating.");
      return;
    }

    setActionLoading("allocate-review");
    setActionError(null);
    setActionSuccess(null);

    try {
      if (isBankScopedWorkspace && bankPartnerId) {
        const { error } = await supabase.rpc(
          "bank_allocate_manual_review_allocation",
          {
            p_partner_id: bankPartnerId,
            p_review_id: selectedReview.review_id,
            p_group_id: selectedGroupId,
            p_member_user_id: selectedMemberUserId,
            p_note: allocationNote.trim() || null,
          },
        );

        if (error) {
          throw new Error(error.message);
        }
      } else {
        const { error } = await supabase.rpc(
          "admin_allocate_momo_sms_manual_review_to_group_member",
          {
            p_review_id: selectedReview.review_id,
            p_group_id: selectedGroupId,
            p_member_user_id: selectedMemberUserId,
            p_note: allocationNote.trim() || null,
          },
        );

        if (error) {
          throw new Error(error.message);
        }
      }

      setActionSuccess("Manual review allocated successfully.");
      setSelectedReviewId(null);
      setSelectedMemberUserId("");
      setAllocationNote("");
      await refreshTransactionWorkspaces();
    } catch (error) {
      setActionError(
        error instanceof Error ? error.message : "Failed to allocate manual review.",
      );
    } finally {
      setActionLoading(null);
    }
  };

  const handleRejectReview = async (review: ManualReviewRow) => {
    setActionLoading(`reject-${review.review_id}`);
    setActionError(null);
    setActionSuccess(null);

    try {
      if (isBankScopedWorkspace && bankPartnerId) {
        const { error } = await supabase.rpc(
          "bank_reject_manual_review_allocation",
          {
            p_partner_id: bankPartnerId,
            p_review_id: review.review_id,
            p_note: allocationNote.trim() || null,
          },
        );

        if (error) {
          throw new Error(error.message);
        }
      } else {
        const { error } = await supabase.rpc(
          "admin_reject_momo_sms_manual_review",
          {
            p_review_id: review.review_id,
            p_note: allocationNote.trim() || null,
          },
        );

        if (error) {
          throw new Error(error.message);
        }
      }

      if (selectedReviewId === review.review_id) {
        setSelectedReviewId(null);
      }

      setActionSuccess("Manual review rejected successfully.");
      await refreshTransactionWorkspaces();
    } catch (error) {
      setActionError(
        error instanceof Error ? error.message : "Failed to reject manual review.",
      );
    } finally {
      setActionLoading(null);
    }
  };

  const handleAllocateLedgerEntry = async () => {
    if (!selectedLedgerId || !selectedGroupId || !selectedLedgerMemberUserId) {
      setActionError("Select a group, ledger row, and member before allocating.");
      return;
    }

    setActionLoading("allocate-ledger");
    setActionError(null);
    setActionSuccess(null);

    try {
      const { error } = await supabase.rpc("allocate_transaction_to_member", {
        p_ledger_id: selectedLedgerId,
        p_group_id: selectedGroupId,
        p_member_user_id: selectedLedgerMemberUserId,
      });

      if (error) {
        throw new Error(error.message);
      }

      setActionSuccess("Ledger entry allocated to the selected member.");
      await Promise.all([refetchLedgerEntries(), refetchContributions()]);
    } catch (error) {
      setActionError(
        error instanceof Error ? error.message : "Failed to allocate ledger entry.",
      );
    } finally {
      setActionLoading(null);
    }
  };

  const handleUnallocateLedgerEntry = async () => {
    if (!selectedLedgerId || !selectedGroupId) {
      setActionError("Select an allocated ledger entry first.");
      return;
    }

    setActionLoading("unallocate-ledger");
    setActionError(null);
    setActionSuccess(null);

    try {
      const { error } = await supabase.rpc("unallocate_transaction", {
        p_ledger_id: selectedLedgerId,
        p_group_id: selectedGroupId,
      });

      if (error) {
        throw new Error(error.message);
      }

      setActionSuccess("Ledger entry returned to the unallocated wallet queue.");
      await refetchLedgerEntries();
    } catch (error) {
      setActionError(
        error instanceof Error ? error.message : "Failed to unallocate ledger entry.",
      );
    } finally {
      setActionLoading(null);
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-zinc-900">Contributions</h1>
          <p className="text-sm text-zinc-500 mt-1">
            Confirmed contributions, manual-review queue, and group allocation workspace.
          </p>
        </div>
        <div className="flex items-center gap-3">
          <Button onClick={() => void refreshTransactionWorkspaces()} variant="outline">
            <RefreshCw className="h-4 w-4 mr-2" /> Refresh
          </Button>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="outline"><Download className="h-4 w-4 mr-2" /> Export</Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-44">
              <DropdownMenuItem onClick={() => exportToCSV(filtered, "contributions", [
                { key: "user_name", label: "Member" },
                { key: "user_phone", label: "Phone" },
                { key: "group_name", label: "Group" },
                { key: "amount", label: "Amount (RWF)" },
                { key: "momo_reference", label: "Reference" },
                { key: "status", label: "Status" },
                { key: "created_at", label: "Date" },
              ])}><Download className="mr-2 h-4 w-4" /> Export CSV</DropdownMenuItem>
              <DropdownMenuItem onClick={() => exportToTSV(filtered, "contributions", [
                { key: "user_name", label: "Member" },
                { key: "user_phone", label: "Phone" },
                { key: "group_name", label: "Group" },
                { key: "amount", label: "Amount (RWF)" },
                { key: "momo_reference", label: "Reference" },
                { key: "status", label: "Status" },
                { key: "created_at", label: "Date" },
              ])}><FileSpreadsheet className="mr-2 h-4 w-4" /> Export Excel</DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      </div>

      {actionError && (
        <div className="rounded-xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-700">
          {actionError}
        </div>
      )}
      {actionSuccess && (
        <div className="rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-700">
          {actionSuccess}
        </div>
      )}

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

        {contributionsLoading && !contributionData ? (
          <div className="flex h-48 items-center justify-center">
            <Loader2 className="h-8 w-8 animate-spin text-indigo-600" />
          </div>
        ) : contributionsError ? (
          <div className="flex h-48 flex-col items-center justify-center gap-4">
            <AlertTriangleIcon className="h-10 w-10 text-amber-500" />
            <p className="text-sm text-zinc-600">{contributionsError}</p>
            <Button onClick={refetchContributions} variant="outline" size="sm">
              <RefreshCw className="h-4 w-4 mr-2" /> Retry
            </Button>
          </div>
        ) : (
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
                  <TableCell className="font-mono text-xs text-zinc-600">{txn.user_phone ?? "—"}</TableCell>
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
                      <DropdownMenuContent align="end" className="w-52">
                        <DropdownMenuLabel>Actions</DropdownMenuLabel>
                        <DropdownMenuSeparator />
                        <DropdownMenuItem onClick={() => setSelectedContributionId(txn.id)}>
                          <Eye className="mr-2 h-4 w-4" /> View Details
                        </DropdownMenuItem>
                        <DropdownMenuItem onClick={() => handleContributionReceiptDownload(txn)}>
                          <Download className="mr-2 h-4 w-4" /> Download Receipt
                        </DropdownMenuItem>
                        {txn.group_id && (
                          <DropdownMenuItem onClick={() => setSelectedGroupId(txn.group_id ?? "")}>
                            <Link2 className="mr-2 h-4 w-4" /> Open Group Workspace
                          </DropdownMenuItem>
                        )}
                      </DropdownMenuContent>
                    </DropdownMenu>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}

        <div className="flex items-center justify-between p-4 border-t border-zinc-100">
          <p className="text-sm text-zinc-500">
            Showing {total === 0 ? 0 : page * PAGE_SIZE + 1}–{Math.min((page + 1) * PAGE_SIZE, total)} of {total}
          </p>
          <div className="flex gap-2">
            <Button variant="outline" size="sm" disabled={page === 0} onClick={() => setPage(page - 1)}>Previous</Button>
            <Button variant="outline" size="sm" disabled={(page + 1) * PAGE_SIZE >= total} onClick={() => setPage(page + 1)}>Next</Button>
          </div>
        </div>
      </Card>

      {selectedContribution && (
        <Card>
          <CardHeader>
            <CardTitle>Contribution Detail</CardTitle>
            <CardDescription>
              Selected contribution record for audit and UAT verification.
            </CardDescription>
          </CardHeader>
          <CardContent className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <div>
              <p className="text-xs font-medium uppercase tracking-wide text-zinc-500">Contribution ID</p>
              <p className="mt-1 font-mono text-sm text-zinc-900">{selectedContribution.id}</p>
            </div>
            <div>
              <p className="text-xs font-medium uppercase tracking-wide text-zinc-500">Member</p>
              <p className="mt-1 text-sm text-zinc-900">{selectedContribution.user_name}</p>
            </div>
            <div>
              <p className="text-xs font-medium uppercase tracking-wide text-zinc-500">Group</p>
              <p className="mt-1 text-sm text-zinc-900">{selectedContribution.group_name}</p>
            </div>
            <div>
              <p className="text-xs font-medium uppercase tracking-wide text-zinc-500">Status</p>
              <p className="mt-1 text-sm text-zinc-900">{selectedContribution.status}</p>
            </div>
            <div>
              <p className="text-xs font-medium uppercase tracking-wide text-zinc-500">Amount</p>
              <p className="mt-1 text-sm text-zinc-900">{selectedContribution.amount.toLocaleString()} RWF</p>
            </div>
            <div>
              <p className="text-xs font-medium uppercase tracking-wide text-zinc-500">Phone</p>
              <p className="mt-1 text-sm text-zinc-900">{selectedContribution.user_phone ?? "—"}</p>
            </div>
            <div>
              <p className="text-xs font-medium uppercase tracking-wide text-zinc-500">Reference</p>
              <p className="mt-1 font-mono text-sm text-zinc-900">{selectedContribution.momo_reference ?? "—"}</p>
            </div>
            <div>
              <p className="text-xs font-medium uppercase tracking-wide text-zinc-500">Created</p>
              <p className="mt-1 text-sm text-zinc-900">{formatDateTime(selectedContribution.created_at)}</p>
            </div>
          </CardContent>
        </Card>
      )}

      <div className="grid grid-cols-1 gap-6 xl:grid-cols-[minmax(0,1.35fr)_minmax(380px,0.85fr)]">
        <Card>
          <CardHeader>
            <CardTitle>Manual Review Queue</CardTitle>
            <CardDescription>
              Resolve unresolved MoMo SMS records, or close them as not app linked.
            </CardDescription>
          </CardHeader>
          <CardContent>
            {manualReviewsLoading && !manualReviewData ? (
              <div className="flex h-48 items-center justify-center">
                <Loader2 className="h-8 w-8 animate-spin text-indigo-600" />
              </div>
            ) : manualReviewsError ? (
              <div className="flex h-48 flex-col items-center justify-center gap-4">
                <AlertTriangleIcon className="h-10 w-10 text-amber-500" />
                <p className="text-sm text-zinc-600">{manualReviewsError}</p>
                <Button onClick={refetchManualReviews} variant="outline" size="sm">
                  <RefreshCw className="h-4 w-4 mr-2" /> Retry
                </Button>
              </div>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Payer</TableHead>
                    <TableHead>Group</TableHead>
                    <TableHead>Amount</TableHead>
                    <TableHead>Reason</TableHead>
                    <TableHead>Updated</TableHead>
                    <TableHead className="text-right">Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {filteredManualReviews.length === 0 ? (
                    <TableRow>
                      <TableCell colSpan={6} className="h-32 text-center">
                        <div className="flex flex-col items-center gap-2 text-zinc-400">
                          <ShieldAlert className="h-8 w-8" />
                          <p className="text-sm">No manual-review items found</p>
                        </div>
                      </TableCell>
                    </TableRow>
                  ) : filteredManualReviews.map((review: ManualReviewRow) => (
                    <TableRow key={review.review_id}>
                      <TableCell>
                        <div>
                          <p className="font-medium text-zinc-900">{review.payer_name}</p>
                          {(review.provider || review.payee_digits) && (
                            <p className="text-xs text-zinc-500">
                              {[review.provider, review.payee_digits].filter(Boolean).join(" / ")}
                            </p>
                          )}
                        </div>
                      </TableCell>
                      <TableCell className="text-zinc-600">{review.group_name ?? "Select at allocation time"}</TableCell>
                      <TableCell className="font-medium text-zinc-900">{review.amount.toLocaleString()} RWF</TableCell>
                      <TableCell>
                        <div className="max-w-[240px]">
                          <p className="text-sm text-zinc-700">{review.reason}</p>
                          <Badge variant={review.match_status === "rejected" ? "danger" : "warning"} className="mt-2">
                            {review.match_status}
                          </Badge>
                        </div>
                      </TableCell>
                      <TableCell className="text-sm text-zinc-500">{formatDateTime(review.updated_at)}</TableCell>
                      <TableCell className="text-right">
                        <DropdownMenu>
                          <DropdownMenuTrigger asChild>
                            <Button variant="ghost" size="icon">
                              <MoreHorizontal className="h-4 w-4 text-zinc-400" />
                            </Button>
                          </DropdownMenuTrigger>
                          <DropdownMenuContent align="end" className="w-56">
                            <DropdownMenuLabel>Actions</DropdownMenuLabel>
                            <DropdownMenuSeparator />
                            <DropdownMenuItem onClick={() => handlePrepareReview(review)}>
                              <CheckCircle2 className="mr-2 h-4 w-4" /> Prepare Allocation
                            </DropdownMenuItem>
                            <DropdownMenuItem
                              onClick={() => {
                                setSelectedReviewId(review.review_id);
                                if (review.group_id) {
                                  setSelectedGroupId(review.group_id);
                                }
                                void handleRejectReview(review);
                              }}
                              className="text-rose-600 focus:text-rose-600"
                            >
                              <XCircle className="mr-2 h-4 w-4" /> Reject Review
                            </DropdownMenuItem>
                          </DropdownMenuContent>
                        </DropdownMenu>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Manual Allocation Workspace</CardTitle>
            <CardDescription>
              Route a selected manual-review SMS to the correct savings member and group.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            {!selectedReview ? (
              <div className="rounded-xl border border-dashed border-zinc-200 bg-zinc-50 px-4 py-6 text-sm text-zinc-500">
                Pick a manual-review record from the queue to prepare an allocation.
              </div>
            ) : (
              <>
                <div className="rounded-xl border border-zinc-200 bg-zinc-50 px-4 py-4 space-y-2">
                  <p className="font-medium text-zinc-900">{selectedReview.payer_name}</p>
                  <p className="text-sm text-zinc-600">
                    {selectedReview.amount.toLocaleString()} {selectedReview.currency ?? "RWF"} • {selectedReview.reason}
                  </p>
                  {selectedReview.sms_preview && (
                    <p className="text-xs leading-5 text-zinc-500">{selectedReview.sms_preview}</p>
                  )}
                  <p className="text-xs font-mono text-zinc-500">
                    Review ID: {selectedReview.review_id}
                  </p>
                </div>

                <div className="space-y-2">
                  <label className="text-sm font-medium text-zinc-900">Target Group</label>
                  <select
                    value={selectedGroupId}
                    onChange={(event) => {
                      setSelectedGroupId(event.target.value);
                      setSelectedMemberUserId("");
                      setSelectedLedgerId(null);
                      setSelectedLedgerMemberUserId("");
                    }}
                    className="w-full h-10 px-3 rounded-lg border border-zinc-200 bg-white text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
                    disabled={groupsLoading}
                  >
                    <option value="">Select a savings group…</option>
                    {(groupOptions ?? []).map((group: GroupOption) => (
                      <option key={group.id} value={group.id}>
                        {group.name}
                      </option>
                    ))}
                  </select>
                  {groupsError && <p className="text-xs text-rose-600">{groupsError}</p>}
                </div>

                <div className="space-y-2">
                  <label className="text-sm font-medium text-zinc-900">Target Member</label>
                  <select
                    value={selectedMemberUserId}
                    onChange={(event) => setSelectedMemberUserId(event.target.value)}
                    className="w-full h-10 px-3 rounded-lg border border-zinc-200 bg-white text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
                    disabled={!selectedGroupId || membersLoading}
                  >
                    <option value="">Select a member…</option>
                    {(groupMembers ?? []).map((member: GroupMemberOption) => (
                      <option key={member.user_id} value={member.user_id}>
                        {member.display_name}{member.phone ? ` (${member.phone})` : ""}
                      </option>
                    ))}
                  </select>
                  {membersError && <p className="text-xs text-rose-600">{membersError}</p>}
                </div>

                <div className="space-y-2">
                  <label className="text-sm font-medium text-zinc-900">Allocation Note</label>
                  <Input
                    value={allocationNote}
                    onChange={(event) => setAllocationNote(event.target.value)}
                    placeholder="Optional audit note..."
                  />
                </div>

                <div className="flex flex-wrap gap-3">
                  <Button
                    onClick={() => void handleAllocateReview()}
                    disabled={actionLoading === "allocate-review" || !selectedReview}
                    className="bg-indigo-600 hover:bg-indigo-700 text-white"
                  >
                    {actionLoading === "allocate-review" ? (
                      <>
                        <Loader2 className="mr-2 h-4 w-4 animate-spin" /> Allocating…
                      </>
                    ) : (
                      <>
                        <Link2 className="mr-2 h-4 w-4" /> Allocate Review
                      </>
                    )}
                  </Button>
                  <Button
                    variant="outline"
                    onClick={() => void handleRejectReview(selectedReview)}
                    disabled={actionLoading === `reject-${selectedReview.review_id}`}
                  >
                    {actionLoading === `reject-${selectedReview.review_id}` ? (
                      <>
                        <Loader2 className="mr-2 h-4 w-4 animate-spin" /> Rejecting…
                      </>
                    ) : (
                      <>
                        <XCircle className="mr-2 h-4 w-4" /> Reject Review
                      </>
                    )}
                  </Button>
                </div>
              </>
            )}
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Group Payment Ledger Allocation</CardTitle>
          <CardDescription>
            Review already-ingested group ledger entries and allocate or unallocate them to the correct member.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-6">
          <div className="grid grid-cols-1 gap-4 lg:grid-cols-[minmax(280px,0.5fr)_minmax(0,1fr)]">
            <div className="space-y-4">
              <div className="space-y-2">
                <label className="text-sm font-medium text-zinc-900">Savings Group</label>
                <select
                  value={selectedGroupId}
                  onChange={(event) => {
                    setSelectedGroupId(event.target.value);
                    setSelectedLedgerId(null);
                    setSelectedLedgerMemberUserId("");
                  }}
                  className="w-full h-10 px-3 rounded-lg border border-zinc-200 bg-white text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
                  disabled={groupsLoading}
                >
                  <option value="">Select a savings group…</option>
                  {(groupOptions ?? []).map((group: GroupOption) => (
                    <option key={group.id} value={group.id}>
                      {group.name}
                    </option>
                  ))}
                </select>
              </div>

              <div className="rounded-xl border border-zinc-200 bg-zinc-50 px-4 py-4 space-y-2">
                <p className="text-sm font-medium text-zinc-900">{selectedGroupId ? selectedGroupName : "No group selected"}</p>
                <p className="text-xs text-zinc-500">
                  This workspace uses the audited group-allocation RPCs and is safe for correcting member attribution.
                </p>
              </div>

              {selectedLedgerEntry && (
                <div className="rounded-xl border border-zinc-200 bg-white px-4 py-4 space-y-3">
                  <div>
                    <p className="text-xs font-medium uppercase tracking-wide text-zinc-500">Selected Ledger Entry</p>
                    <p className="mt-1 font-mono text-sm text-zinc-900">{selectedLedgerEntry.ledger_id}</p>
                  </div>
                  <div>
                    <p className="text-xs font-medium uppercase tracking-wide text-zinc-500">Current Payer</p>
                    <p className="mt-1 text-sm text-zinc-900">{selectedLedgerEntry.payer_name}</p>
                  </div>
                  <div>
                    <p className="text-xs font-medium uppercase tracking-wide text-zinc-500">Current Status</p>
                    <Badge variant={isAllocatedLedgerEntry(selectedLedgerEntry) ? "success" : "warning"} className="mt-1">
                      {isAllocatedLedgerEntry(selectedLedgerEntry) ? "Allocated" : "Pending member allocation"}
                    </Badge>
                  </div>
                  <div className="space-y-2">
                    <label className="text-sm font-medium text-zinc-900">Allocate To Member</label>
                    <select
                      value={selectedLedgerMemberUserId}
                      onChange={(event) => setSelectedLedgerMemberUserId(event.target.value)}
                      className="w-full h-10 px-3 rounded-lg border border-zinc-200 bg-white text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
                      disabled={!selectedGroupId || membersLoading}
                    >
                      <option value="">Select a member…</option>
                      {(groupMembers ?? []).map((member: GroupMemberOption) => (
                        <option key={member.user_id} value={member.user_id}>
                          {member.display_name}{member.phone ? ` (${member.phone})` : ""}
                        </option>
                      ))}
                    </select>
                  </div>

                  <div className="flex flex-wrap gap-3">
                    <Button
                      onClick={() => void handleAllocateLedgerEntry()}
                      disabled={actionLoading === "allocate-ledger"}
                      className="bg-indigo-600 hover:bg-indigo-700 text-white"
                    >
                      {actionLoading === "allocate-ledger" ? (
                        <>
                          <Loader2 className="mr-2 h-4 w-4 animate-spin" /> Applying…
                        </>
                      ) : (
                        <>
                          <CheckCircle2 className="mr-2 h-4 w-4" /> Allocate Entry
                        </>
                      )}
                    </Button>
                    <Button
                      variant="outline"
                      onClick={() => void handleUnallocateLedgerEntry()}
                      disabled={actionLoading === "unallocate-ledger" || !isAllocatedLedgerEntry(selectedLedgerEntry)}
                    >
                      {actionLoading === "unallocate-ledger" ? (
                        <>
                          <Loader2 className="mr-2 h-4 w-4 animate-spin" /> Removing…
                        </>
                      ) : (
                        <>
                          <XCircle className="mr-2 h-4 w-4" /> Unallocate Entry
                        </>
                      )}
                    </Button>
                  </div>
                </div>
              )}
            </div>

            <div>
              {ledgerLoading && selectedGroupId ? (
                <div className="flex h-48 items-center justify-center">
                  <Loader2 className="h-8 w-8 animate-spin text-indigo-600" />
                </div>
              ) : ledgerError ? (
                <div className="flex h-48 flex-col items-center justify-center gap-4">
                  <AlertTriangleIcon className="h-10 w-10 text-amber-500" />
                  <p className="text-sm text-zinc-600">{ledgerError}</p>
                  <Button onClick={refetchLedgerEntries} variant="outline" size="sm">
                    <RefreshCw className="h-4 w-4 mr-2" /> Retry
                  </Button>
                </div>
              ) : !selectedGroupId ? (
                <div className="rounded-xl border border-dashed border-zinc-200 bg-zinc-50 px-4 py-8 text-sm text-zinc-500">
                  Select a savings group to load its payee ledger entries.
                </div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Payer</TableHead>
                      <TableHead>Amount</TableHead>
                      <TableHead>Reference</TableHead>
                      <TableHead>Label</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead className="text-right">Select</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {(groupLedgerEntries ?? []).length === 0 ? (
                      <TableRow>
                        <TableCell colSpan={6} className="h-32 text-center">
                          <div className="flex flex-col items-center gap-2 text-zinc-400">
                            <Inbox className="h-8 w-8" />
                            <p className="text-sm">No group ledger entries found</p>
                          </div>
                        </TableCell>
                      </TableRow>
                    ) : (groupLedgerEntries ?? []).map((entry: GroupLedgerRow) => (
                      <TableRow key={entry.ledger_id}>
                        <TableCell>
                          <div>
                            <p className="font-medium text-zinc-900">{entry.payer_name}</p>
                            <p className="text-xs text-zinc-500">{entry.payer_phone ?? formatDateTime(entry.tx_datetime)}</p>
                          </div>
                        </TableCell>
                        <TableCell className="font-medium text-zinc-900">{entry.amount.toLocaleString()} {entry.currency ?? "RWF"}</TableCell>
                        <TableCell className="font-mono text-xs text-zinc-500">{entry.external_reference ?? "—"}</TableCell>
                        <TableCell className="text-sm text-zinc-600">{entry.statement_label ?? entry.counterparty_name ?? entry.tx_category ?? "—"}</TableCell>
                        <TableCell>
                          <Badge variant={isAllocatedLedgerEntry(entry) ? "success" : "warning"}>
                            {isAllocatedLedgerEntry(entry) ? "Allocated" : "Needs member"}
                          </Badge>
                        </TableCell>
                        <TableCell className="text-right">
                          <Button
                            variant="outline"
                            size="sm"
                            onClick={() => {
                              setSelectedLedgerId(entry.ledger_id);
                              setSelectedLedgerMemberUserId(entry.payer_user_id ?? "");
                            }}
                          >
                            Select
                          </Button>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
