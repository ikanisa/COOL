import { supabase } from "@/lib/supabase";

export interface RoleAssignment {
  id: string;
  user_id: string;
  user_name: string;
  user_phone: string;
  role: string;
  partner_scope_id: string | null;
  partner_name: string | null;
  granted_at: string;
  is_active: boolean;
}

export interface AppConfigRow {
  key: string;
  value: string;
  description: string | null;
}

export interface PartnerRow {
  id: string;
  name: string;
  category: string;
  momo_code: string | null;
}

export async function listAppConfig(): Promise<AppConfigRow[]> {
  const { data, error } = await supabase
    .from("app_config")
    .select("key, value, description")
    .order("key");
  if (error) throw new Error(error.message);
  return (data ?? []) as AppConfigRow[];
}

export async function listActiveRoleAssignments(): Promise<RoleAssignment[]> {
  const { data, error } = await supabase.rpc("list_admin_role_assignments", {
    p_role: null,
    p_active_only: true,
  });
  if (error) throw new Error(error.message);
  return (data ?? []) as RoleAssignment[];
}

export async function listBankPartners(): Promise<PartnerRow[]> {
  const { data, error } = await supabase
    .from("partners")
    .select("id, name, category, momo_code")
    .eq("category", "bank")
    .order("name");
  if (error) throw new Error(error.message);
  return (data ?? []) as PartnerRow[];
}

export async function revokeAdminRole(assignmentId: string): Promise<void> {
  const { error } = await supabase.rpc("revoke_admin_role", {
    p_assignment_id: assignmentId,
  });
  if (error) throw new Error(error.message);
}
