import type { LucideIcon } from "lucide-react";
import {
  Activity,
  Banknote,
  FileText,
  Fingerprint,
  Layers,
  LayoutDashboard,
  Settings,
  ShieldAlert,
  User,
  Users,
  Wallet,
} from "lucide-react";
import type { AdminAccess, AdminCapabilities } from "@/lib/auth";

export type AdminCapability = keyof AdminCapabilities;

export interface AdminAccessRequirement {
  anyOf?: AdminCapability[];
  allOf?: AdminCapability[];
  allowAnyAdmin?: boolean;
}

export interface AdminNavItem {
  icon: LucideIcon;
  label: string;
  path: string;
  end?: boolean;
  access: AdminAccessRequirement;
}

export const adminRouteAccess = {
  dashboard: { anyOf: ["view_analytics"] },
  users: { anyOf: ["manage_users"] },
  createUser: { anyOf: ["manage_users"] },
  members: { anyOf: ["view_groups", "manage_users"] },
  createMember: { anyOf: ["manage_users"] },
  groups: { anyOf: ["view_groups"] },
  createGroup: { anyOf: ["manage_platform"] },
  transactions: { anyOf: ["view_groups", "view_savings"] },
  loans: { anyOf: ["view_savings"] },
  reconciliation: { anyOf: ["view_groups", "view_savings"] },
  biopay: { anyOf: ["view_savings", "manage_platform"] },
  approvals: { anyOf: ["manage_platform"] },
  health: { anyOf: ["manage_platform", "view_audit_log"] },
  profile: { allowAnyAdmin: true },
  settings: { anyOf: ["manage_config", "manage_roles"] },
} satisfies Record<string, AdminAccessRequirement>;

export const adminNavItems: AdminNavItem[] = [
  {
    icon: LayoutDashboard,
    label: "Dashboard",
    path: "/",
    end: true,
    access: adminRouteAccess.dashboard,
  },
  {
    icon: User,
    label: "User Management",
    path: "/users",
    access: adminRouteAccess.users,
  },
  {
    icon: Users,
    label: "Members",
    path: "/members",
    access: adminRouteAccess.members,
  },
  {
    icon: Layers,
    label: "Groups",
    path: "/groups",
    access: adminRouteAccess.groups,
  },
  {
    icon: Wallet,
    label: "Transactions",
    path: "/transactions",
    access: adminRouteAccess.transactions,
  },
  {
    icon: Banknote,
    label: "Loans",
    path: "/loans",
    access: adminRouteAccess.loans,
  },
  {
    icon: FileText,
    label: "Allocation",
    path: "/reconciliation",
    access: adminRouteAccess.reconciliation,
  },
  {
    icon: Fingerprint,
    label: "BioPay",
    path: "/biopay",
    access: adminRouteAccess.biopay,
  },
  {
    icon: ShieldAlert,
    label: "Approvals",
    path: "/approvals",
    access: adminRouteAccess.approvals,
  },
  {
    icon: Activity,
    label: "System Health",
    path: "/health",
    access: adminRouteAccess.health,
  },
  {
    icon: User,
    label: "Profile",
    path: "/profile",
    access: adminRouteAccess.profile,
  },
  {
    icon: Settings,
    label: "Settings",
    path: "/settings",
    access: adminRouteAccess.settings,
  },
];

export function hasAnyAdminAccess(access: AdminAccess | null): boolean {
  if (!access) return false;
  return (
    access.has_platform_access ||
    access.has_bank_access ||
    access.has_partner_access ||
    Object.values(access.capabilities).some(Boolean)
  );
}

export function hasAdminAccess(
  access: AdminAccess | null,
  requirement: AdminAccessRequirement
): boolean {
  if (!hasAnyAdminAccess(access)) return false;
  if (!access) return false;
  if (requirement.allowAnyAdmin) return true;

  const capabilities = access.capabilities;
  const anyOf = requirement.anyOf ?? [];
  const allOf = requirement.allOf ?? [];

  const hasAnyRequired =
    anyOf.length === 0 || anyOf.some((capability) => capabilities[capability]);
  const hasAllRequired = allOf.every((capability) => capabilities[capability]);

  return hasAnyRequired && hasAllRequired;
}

export function firstAccessibleAdminPath(access: AdminAccess | null): string {
  return (
    adminNavItems.find((item) => hasAdminAccess(access, item.access))?.path ??
    "/profile"
  );
}
