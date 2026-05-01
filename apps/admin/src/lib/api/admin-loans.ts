import { supabase } from "@/lib/supabase";
import { buildAdminIlikeOrFilter } from "@cool/shared-utils/admin-search";

export interface AdminLoanRow {
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

export interface AdminLoansPage {
  rows: AdminLoanRow[];
  total: number;
}

export type AdminLoansSummary = Record<string, number>;

export interface LoanGroupOption {
  id: string;
  name: string;
}

export interface LoanMemberOption {
  id: string;
  display_name: string;
  user_id: string;
  user_phone: string;
}

export interface CreateAdminLoanInput {
  memberId: string;
  groupId: string;
  loanType: string;
  initialAmount: number;
  repaymentAmount: number;
  repaymentFrequency: string;
  dueDate: string;
  notes: string;
}

export async function getAdminLoansSummary(): Promise<AdminLoansSummary> {
  const { data, error } = await supabase.rpc("get_admin_loans_summary");
  if (error) throw new Error(error.message);
  return data as AdminLoansSummary;
}

export async function listAdminLoans(options: {
  page: number;
  pageSize: number;
  status: string | null;
  search: string;
}): Promise<AdminLoansPage> {
  const from = options.page * options.pageSize;
  const to = from + options.pageSize - 1;
  let query = supabase
    .from("loans")
    .select(
      `
        id, loan_code, loan_type, initial_amount, total_paid,
        repayment_amount, repayment_frequency, status, issued_at, due_date, notes,
        users!loans_member_id_fkey ( full_name, phone ),
        groups!loans_group_id_fkey ( name )
      `,
      { count: "exact" }
    )
    .order("issued_at", { ascending: false })
    .range(from, to);

  if (options.status) {
    query = query.eq("status", options.status);
  }

  const searchFilter = buildAdminIlikeOrFilter(options.search, [
    "loan_code",
    "users.full_name",
    "users.phone",
    "groups.name",
  ]);
  if (searchFilter) {
    query = query.or(searchFilter);
  }

  const { data, error, count } = await query;
  if (error) throw new Error(error.message);

  const rows: AdminLoanRow[] = (data ?? []).map((row) => {
    const record = row as Record<string, unknown>;
    const user = record.users as Record<string, string> | null;
    const group = record.groups as Record<string, string> | null;
    const initialAmount = Number(record.initial_amount ?? 0);
    const totalPaid = Number(record.total_paid ?? 0);

    return {
      id: record.id as string,
      loan_code: record.loan_code as string,
      loan_type: record.loan_type as string,
      initial_amount: initialAmount,
      total_paid: totalPaid,
      balance: initialAmount - totalPaid,
      repayment_amount: Number(record.repayment_amount ?? 0),
      repayment_frequency: record.repayment_frequency as string,
      status: record.status as string,
      issued_at: record.issued_at as string,
      due_date: (record.due_date as string | null) ?? null,
      notes: (record.notes as string | null) ?? null,
      member_name: user?.full_name ?? "(Unknown)",
      member_phone: user?.phone ?? "",
      group_name: group?.name ?? "(Unknown)",
    };
  });

  return { rows, total: count ?? 0 };
}

export async function listLoanGroupOptions(): Promise<LoanGroupOption[]> {
  const { data, error } = await supabase
    .from("groups")
    .select("id, name")
    .eq("type", "saving")
    .order("name");
  if (error) throw new Error(error.message);
  return (data ?? []) as LoanGroupOption[];
}

export async function listLoanMemberOptions(
  groupId: string
): Promise<LoanMemberOption[]> {
  if (!groupId) return [];

  const { data, error } = await supabase
    .from("group_members")
    .select(
      `
        id, display_name, user_id,
        users!group_members_user_id_fkey ( phone )
      `
    )
    .eq("group_id", groupId)
    .order("display_name");
  if (error) throw new Error(error.message);

  return (data ?? []).map((row) => {
    const record = row as Record<string, unknown>;
    return {
      id: record.id as string,
      display_name: record.display_name as string,
      user_id: record.user_id as string,
      user_phone:
        (record.users as Record<string, string> | null)?.phone ?? "",
    };
  });
}

export async function createAdminLoan(input: CreateAdminLoanInput): Promise<void> {
  const { data, error } = await supabase.rpc("admin_create_loan", {
    p_member_id: input.memberId,
    p_group_id: input.groupId,
    p_loan_type: input.loanType,
    p_initial_amount: input.initialAmount,
    p_repayment_amount: input.repaymentAmount,
    p_repayment_frequency: input.repaymentFrequency,
    p_due_date: input.dueDate || null,
    p_notes: input.notes.trim() || null,
  });

  if (error) throw new Error(error.message);
  if (data?.status !== "success") {
    throw new Error(data?.message ?? "Failed to create loan.");
  }
}
