import { supabase } from "@/lib/supabase";
import { buildAdminIlikeOrFilter } from "@cool/shared-utils/admin-search";

export interface GroupOption {
  id: string;
  name: string;
}

export interface UserSearchResult {
  id: string;
  full_name: string;
  phone: string;
}

export interface MemberRow {
  id: string;
  group_id: string;
  user_id: string;
  display_name: string;
  is_admin: boolean;
  contribution_amount: number;
  joined_at: string;
  group_name: string;
  user_phone: string;
}

export interface MembersPage {
  rows: MemberRow[];
  total: number;
}

export async function listSavingsGroupOptions(): Promise<GroupOption[]> {
  const { data, error } = await supabase
    .from("groups")
    .select("id, name")
    .eq("type", "saving")
    .order("name");
  if (error) throw new Error(error.message);
  return (data ?? []) as GroupOption[];
}

export async function listAdminMembers(options: {
  page: number;
  pageSize: number;
  search: string;
}): Promise<MembersPage> {
  const from = options.page * options.pageSize;
  const to = from + options.pageSize - 1;
  let query = supabase
    .from("group_members")
    .select(
      `
        id, group_id, user_id, display_name, is_admin, contribution_amount, joined_at,
        groups!group_members_group_id_fkey ( name ),
        users!group_members_user_id_fkey ( phone )
      `,
      { count: "exact" },
    )
    .order("joined_at", { ascending: false })
    .range(from, to);

  const searchFilter = buildAdminIlikeOrFilter(
    options.search,
    ["display_name", "groups.name", "users.phone"],
    { minLength: 3 },
  );
  if (searchFilter) {
    query = query.or(searchFilter);
  }

  const { data, error, count } = await query;
  if (error) throw new Error(error.message);

  const rows: MemberRow[] = (data ?? []).map((row) => {
    const record = row as Record<string, unknown>;
    const group = record.groups as Record<string, string> | null;
    const user = record.users as Record<string, string> | null;
    return {
      id: record.id as string,
      group_id: record.group_id as string,
      user_id: record.user_id as string,
      display_name: record.display_name as string,
      is_admin: record.is_admin as boolean,
      contribution_amount: record.contribution_amount as number,
      joined_at: record.joined_at as string,
      group_name: group?.name ?? "(Unknown)",
      user_phone: user?.phone ?? "",
    };
  });

  return { rows, total: count ?? 0 };
}

export async function searchAdminUsers(
  search: string,
): Promise<UserSearchResult[]> {
  const searchFilter = buildAdminIlikeOrFilter(
    search,
    ["full_name", "phone"],
    { minLength: 3 },
  );
  if (!searchFilter) return [];

  const { data, error } = await supabase
    .from("users")
    .select("id, full_name, phone")
    .or(searchFilter)
    .limit(10);

  if (error) throw new Error(error.message);
  return (data ?? []) as UserSearchResult[];
}

export async function addAdminGroupMember(options: {
  groupId: string;
  userId: string;
  displayName: string;
}): Promise<void> {
  const { data, error } = await supabase.rpc("admin_add_group_member", {
    p_group_id: options.groupId,
    p_user_id: options.userId,
    p_display_name: options.displayName.trim() || null,
  });
  if (error) throw new Error(error.message);
  if (data?.status !== "success") {
    throw new Error(data?.message ?? "Failed to add member.");
  }
}
