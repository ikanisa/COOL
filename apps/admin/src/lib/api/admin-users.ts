import { supabase } from "@/lib/supabase";
import { buildAdminIlikeOrFilter } from "@cool/shared-utils/admin-search";

export interface AdminUserRow {
  id: string;
  phone: string;
  full_name: string;
  country: string;
  is_admin: boolean;
  is_mock: boolean;
  created_at: string;
  momo_number: string | null;
}

export interface AdminUsersPage {
  rows: AdminUserRow[];
  total: number;
}

export interface CreateAdminUserInput {
  fullName: string;
  phone: string;
  isAdmin: boolean;
}

export async function listAdminUsers(options: {
  page: number;
  pageSize: number;
  search: string;
}): Promise<AdminUsersPage> {
  const from = options.page * options.pageSize;
  const to = from + options.pageSize - 1;
  let query = supabase
    .from("users")
    .select(
      "id, phone, full_name, country, is_admin, is_mock, created_at, momo_number",
      { count: "exact" }
    )
    .order("created_at", { ascending: false })
    .range(from, to);

  const searchFilter = buildAdminIlikeOrFilter(options.search, [
    "full_name",
    "phone",
  ]);
  if (searchFilter) {
    query = query.or(searchFilter);
  }

  const { data, error, count } = await query;
  if (error) throw new Error(error.message);
  return { rows: (data ?? []) as AdminUserRow[], total: count ?? 0 };
}

function normalizeRwandaPhone(phone: string): string {
  const compact = phone.replace(/\s/g, "");
  if (compact.startsWith("+250")) return compact;
  const local = compact.replace(/^0+/, "");
  return `+250${local}`;
}

export async function createAdminUser(input: CreateAdminUserInput): Promise<void> {
  const { data, error } = await supabase.functions.invoke("admin-create-user", {
    body: {
      phone: normalizeRwandaPhone(input.phone),
      full_name: input.fullName.trim(),
      country: "RW",
      is_admin: input.isAdmin,
    },
  });

  if (error) throw new Error(error.message);
  if (data?.error) throw new Error(data.error);
}
