import { supabase } from "@/lib/supabase";

export interface SavingsGroup {
  id: string;
  name: string;
  description: string | null;
  target_amount: number;
  monthly_contribution: number | null;
  frequency: string;
  member_count: number;
  total_collected: number;
  invite_code: string;
  is_closed: boolean;
  is_active: boolean;
  created_at: string;
}

export interface GroupsData {
  savings_momo_code: string;
  total_savings_groups: number;
  active_savings_groups: number;
  total_community_groups: number;
  total_members_in_savings: number;
  total_collected: number;
  savings_groups: SavingsGroup[];
  community_groups: Array<{
    id: string;
    name: string;
    member_count: number;
    created_at: string;
  }>;
}

export interface CreateSavingsGroupInput {
  name: string;
  description: string;
  targetAmount: string;
  monthlyContribution: string;
  frequency: string;
}

export async function getAdminGroupsDetail(): Promise<GroupsData> {
  const { data, error } = await supabase.rpc("admin_get_savings_groups_detail");
  if (error) throw new Error(error.message);
  return data as GroupsData;
}

export async function createAdminSavingsGroup(
  input: CreateSavingsGroupInput
): Promise<void> {
  const { data, error } = await supabase.rpc("admin_create_savings_group", {
    p_name: input.name.trim(),
    p_description: input.description.trim() || null,
    p_target_amount: input.targetAmount ? parseInt(input.targetAmount) : 0,
    p_monthly_contribution: input.monthlyContribution
      ? parseInt(input.monthlyContribution)
      : null,
    p_frequency: input.frequency,
  });

  if (error) throw new Error(error.message);
  if (data?.status !== "success") {
    throw new Error(data?.message ?? "Failed to create group.");
  }
}
