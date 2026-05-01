import { supabase } from "@/lib/supabase";
import { buildAdminIlikeOrFilter } from "@cool/shared-utils/admin-search";

export interface ContributionRow {
  id: string;
  amount: number;
  status: string;
  momo_reference: string | null;
  created_at: string;
  user_name: string;
  user_phone: string;
  group_name: string;
}

export interface LedgerRow {
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

export interface AdminTransactionsPage<T> {
  rows: T[];
  total: number;
}

export async function listContributionTransactions(options: {
  page: number;
  pageSize: number;
  status: string | null;
  search: string;
}): Promise<AdminTransactionsPage<ContributionRow>> {
  const from = options.page * options.pageSize;
  const to = from + options.pageSize - 1;
  let query = supabase
    .from("group_contributions")
    .select(
      `
        id, amount, status, momo_reference, created_at,
        users!group_contributions_user_id_fkey ( full_name, phone ),
        groups!group_contributions_group_id_fkey ( name )
      `,
      { count: "exact" }
    )
    .order("created_at", { ascending: false })
    .range(from, to);

  if (options.status) {
    query = query.eq("status", options.status);
  }

  const searchFilter = buildAdminIlikeOrFilter(
    options.search,
    ["momo_reference", "users.full_name", "groups.name"],
    { minLength: 3 }
  );
  if (searchFilter) {
    query = query.or(searchFilter);
  }

  const { data, error, count } = await query;
  if (error) throw new Error(error.message);

  const rows: ContributionRow[] = (data ?? []).map((row) => {
    const record = row as Record<string, unknown>;
    const user = record.users as Record<string, string> | null;
    const group = record.groups as Record<string, string> | null;
    return {
      id: record.id as string,
      amount: record.amount as number,
      status: record.status as string,
      momo_reference: record.momo_reference as string | null,
      created_at: record.created_at as string,
      user_name: user?.full_name ?? "(Unknown)",
      user_phone: user?.phone ?? "",
      group_name: group?.name ?? "(Unknown)",
    };
  });

  return { rows, total: count ?? 0 };
}

export async function listLedgerTransactions(options: {
  page: number;
  pageSize: number;
  scope: string | null;
  search: string;
}): Promise<AdminTransactionsPage<LedgerRow>> {
  const from = options.page * options.pageSize;
  const to = from + options.pageSize - 1;
  let query = supabase
    .from("momo_ledger_entries")
    .select(
      `
        id, amount, currency, entry_type, ledger_scope, ledger_status,
        statement_label, counterparty_name, external_reference,
        tx_datetime, created_at,
        users!momo_ledger_entries_user_id_fkey ( full_name, phone )
      `,
      { count: "exact" }
    )
    .order("tx_datetime", { ascending: false })
    .range(from, to);

  if (options.scope) {
    query = query.eq("ledger_scope", options.scope);
  }

  const searchFilter = buildAdminIlikeOrFilter(
    options.search,
    [
      "statement_label",
      "counterparty_name",
      "external_reference",
      "users.full_name",
    ],
    { minLength: 3 }
  );
  if (searchFilter) {
    query = query.or(searchFilter);
  }

  const { data, error, count } = await query;
  if (error) throw new Error(error.message);

  const rows: LedgerRow[] = (data ?? []).map((row) => {
    const record = row as Record<string, unknown>;
    const user = record.users as Record<string, string> | null;
    return {
      id: record.id as string,
      amount: record.amount as number,
      currency: (record.currency as string) ?? "RWF",
      entry_type: (record.entry_type as string) ?? "",
      ledger_scope: (record.ledger_scope as string) ?? "",
      ledger_status: (record.ledger_status as string) ?? "",
      statement_label: (record.statement_label as string) ?? "",
      counterparty_name: record.counterparty_name as string | null,
      external_reference: record.external_reference as string | null,
      tx_datetime:
        (record.tx_datetime as string) ?? (record.created_at as string),
      created_at: record.created_at as string,
      user_name: user?.full_name ?? "(Unknown)",
      user_phone: user?.phone ?? "",
    };
  });

  return { rows, total: count ?? 0 };
}
