import { useEffect, useMemo, useState } from "react";
import {
  AlertTriangle,
  Building2,
  LockKeyhole,
  RefreshCw,
  Settings as SettingsIcon,
  Shield,
  Smartphone,
  Trash2,
} from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import {
  DataTableEmptyRow,
  DataTablePagination,
  DataTableSearch,
  DataTableToolbar,
} from "@/components/ui/data-table-controls";
import { Input } from "@/components/ui/input";
import { PageError, PageLoading } from "@/components/ui/states";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import {
  listActiveRoleAssignments,
  listAppConfig,
  listBankPartners,
  revokeAdminRole,
  type RoleAssignment,
} from "@/lib/api/admin-settings";
import { useAuth } from "@/lib/auth";
import { useDataTableController } from "@/lib/data-table-controller";
import { useAsyncData } from "@/lib/hooks";
import { maskConfigValue } from "@/lib/sensitive-values";

type SettingsTab = "app-config" | "roles" | "partners" | "sms";
const PAGE_SIZE = 20;

function includesQuery(values: Array<string | null | undefined>, query: string): boolean {
  const normalized = query.trim().toLowerCase();
  if (!normalized) return true;
  return values.some((value) => value?.toLowerCase().includes(normalized));
}

export function Settings() {
  const { adminAccess } = useAuth();
  const canManageConfig = adminAccess?.capabilities.manage_config === true;
  const canManageRoles = adminAccess?.capabilities.manage_roles === true;
  const [activeTab, setActiveTab] = useState<SettingsTab>(
    canManageConfig ? "app-config" : "roles"
  );
  const configTable = useDataTableController({ pageSize: PAGE_SIZE });
  const roleTable = useDataTableController({ pageSize: PAGE_SIZE });
  const partnerTable = useDataTableController({ pageSize: PAGE_SIZE });
  const [roleToRevoke, setRoleToRevoke] = useState<RoleAssignment | null>(null);
  const [revoking, setRevoking] = useState(false);

  const {
    data: config,
    loading: configLoading,
    error: configError,
    refetch: refetchConfig,
  } = useAsyncData(
    () => (canManageConfig ? listAppConfig() : Promise.resolve([])),
    [canManageConfig]
  );
  const {
    data: roles,
    loading: rolesLoading,
    error: rolesError,
    refetch: refetchRoles,
  } = useAsyncData(
    () => (canManageRoles ? listActiveRoleAssignments() : Promise.resolve([])),
    [canManageRoles]
  );
  const {
    data: partners,
    loading: partnersLoading,
    error: partnersError,
    refetch: refetchPartners,
  } = useAsyncData(
    () => (canManageConfig ? listBankPartners() : Promise.resolve([])),
    [canManageConfig]
  );

  const tabs = useMemo(
    () =>
      [
        {
          id: "app-config" as const,
          label: "App Configuration",
          icon: SettingsIcon,
          allowed: canManageConfig,
        },
        {
          id: "roles" as const,
          label: "Admin Roles",
          icon: Shield,
          allowed: canManageRoles,
        },
        {
          id: "partners" as const,
          label: "Bank Partners",
          icon: Building2,
          allowed: canManageConfig,
        },
        {
          id: "sms" as const,
          label: "SMS Pipeline",
          icon: Smartphone,
          allowed: canManageConfig,
        },
      ].filter((tab) => tab.allowed),
    [canManageConfig, canManageRoles]
  );

  useEffect(() => {
    if (tabs.length > 0 && !tabs.some((tab) => tab.id === activeTab)) {
      setActiveTab(tabs[0].id);
    }
  }, [activeTab, tabs]);

  const filteredConfig = (config ?? []).filter((row) =>
    includesQuery([row.key, row.description], configTable.search)
  );
  const filteredRoles = (roles ?? []).filter((role) =>
    includesQuery(
      [role.user_name, role.user_phone, role.role, role.partner_name, role.partner_scope_id],
      roleTable.search
    )
  );
  const filteredPartners = (partners ?? []).filter((partner) =>
    includesQuery([partner.name, partner.category, partner.momo_code], partnerTable.search)
  );
  const visibleConfig = configTable.paginate(filteredConfig);
  const visibleRoles = roleTable.paginate(filteredRoles);
  const visiblePartners = partnerTable.paginate(filteredPartners);
  const smsConfig = (config ?? []).filter((row) =>
    /sms|momo|mobile_money/i.test(row.key)
  );

  const confirmRevokeRole = async () => {
    if (!roleToRevoke) return;
    setRevoking(true);
    try {
      await revokeAdminRole(roleToRevoke.id);
      toast.success("Role revoked successfully.");
      setRoleToRevoke(null);
      await refetchRoles();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "Failed to revoke role.");
    } finally {
      setRevoking(false);
    }
  };

  if (tabs.length === 0) {
    return (
      <PageError
        message="Your admin role does not include permission to manage platform settings."
      />
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-zinc-900">Platform Settings</h1>
          <p className="mt-1 text-sm text-zinc-500">
            Configuration, role assignments, partner metadata, and SMS pipeline controls.
          </p>
        </div>
      </div>

      <div className="flex flex-col gap-6 md:flex-row">
        <div className="w-full shrink-0 space-y-1 md:w-64">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              type="button"
              onClick={() => setActiveTab(tab.id)}
              className={`flex w-full items-center gap-3 rounded-lg px-3 py-2.5 text-left text-sm font-semibold transition-colors ${
                activeTab === tab.id
                  ? "bg-indigo-50 text-indigo-700"
                  : "text-zinc-600 hover:bg-zinc-100 hover:text-zinc-900"
              }`}
            >
              <tab.icon className="h-4 w-4" />
              {tab.label}
            </button>
          ))}
        </div>

        <div className="min-w-0 flex-1 space-y-6">
          {activeTab === "app-config" && (
            <Card>
              <CardHeader>
                <CardTitle>Application Configuration</CardTitle>
                <CardDescription>
                  Database-backed app configuration. Sensitive values are hidden in the browser.
                </CardDescription>
              </CardHeader>
              <CardContent>
                <DataTableToolbar className="mb-4 rounded-lg border border-zinc-100 p-0">
                  <DataTableSearch
                    placeholder="Search configuration..."
                    value={configTable.search}
                    onChange={configTable.setSearch}
                  />
                </DataTableToolbar>
                {configLoading ? (
                  <PageLoading message="Loading configuration..." />
                ) : configError ? (
                  <PageError message={configError} onRetry={refetchConfig} />
                ) : (
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Key</TableHead>
                        <TableHead>Value</TableHead>
                        <TableHead>Description</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {filteredConfig.length === 0 ? (
                        <DataTableEmptyRow
                          colSpan={3}
                          message="No configuration rows match this search."
                        />
                      ) : (
                        visibleConfig.map((row) => {
                          const masked = maskConfigValue(row.key, row.value);
                          return (
                            <TableRow key={row.key}>
                              <TableCell className="font-mono text-xs text-zinc-700">{row.key}</TableCell>
                              <TableCell className="max-w-[240px]">
                                <div className="flex items-center gap-2">
                                  {masked.masked && <LockKeyhole className="h-3.5 w-3.5 text-zinc-400" />}
                                  <span className="truncate font-mono text-xs text-zinc-900">
                                    {masked.value}
                                  </span>
                                  {masked.masked && <Badge variant="outline">Hidden</Badge>}
                                </div>
                              </TableCell>
                              <TableCell className="max-w-[360px] truncate text-xs text-zinc-500">
                                {row.description ?? "—"}
                              </TableCell>
                            </TableRow>
                          );
                        })
                      )}
                    </TableBody>
                  </Table>
                )}
                {!configLoading && !configError && (
                  <DataTablePagination
                    page={configTable.page}
                    pageSize={configTable.pageSize}
                    total={filteredConfig.length}
                    onPageChange={configTable.setPage}
                  />
                )}
              </CardContent>
            </Card>
          )}

          {activeTab === "roles" && (
            <Card>
              <CardHeader>
                <CardTitle>Active Role Assignments</CardTitle>
                <CardDescription>
                  Database-backed RBAC from admin_role_assignments. Revocation is audited by the backend RPC.
                </CardDescription>
              </CardHeader>
              <CardContent>
                <DataTableToolbar className="mb-4 rounded-lg border border-zinc-100 p-0">
                  <DataTableSearch
                    placeholder="Search users, roles, or scopes..."
                    value={roleTable.search}
                    onChange={roleTable.setSearch}
                  />
                </DataTableToolbar>
                {rolesLoading ? (
                  <PageLoading message="Loading role assignments..." />
                ) : rolesError ? (
                  <PageError message={rolesError} onRetry={refetchRoles} />
                ) : (
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>User</TableHead>
                        <TableHead>Phone</TableHead>
                        <TableHead>Role</TableHead>
                        <TableHead>Partner Scope</TableHead>
                        <TableHead>Granted</TableHead>
                        <TableHead className="text-right">Actions</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {filteredRoles.length === 0 ? (
                        <DataTableEmptyRow
                          colSpan={6}
                          message="No role assignments match this search."
                        />
                      ) : (
                        visibleRoles.map((role) => (
                          <TableRow key={role.id}>
                            <TableCell className="font-medium text-zinc-900">
                              {role.user_name || "(Unknown)"}
                            </TableCell>
                            <TableCell className="font-mono text-xs text-zinc-500">
                              {role.user_phone || "—"}
                            </TableCell>
                            <TableCell>
                              <Badge
                                variant={role.role === "admin" ? "default" : "outline"}
                                className={role.role === "admin" ? "bg-indigo-100 text-indigo-800" : ""}
                              >
                                {role.role}
                              </Badge>
                            </TableCell>
                            <TableCell className="text-zinc-600">
                              {role.partner_name ?? "Global"}
                            </TableCell>
                            <TableCell className="text-sm text-zinc-500">
                              {new Date(role.granted_at).toLocaleDateString()}
                            </TableCell>
                            <TableCell className="text-right">
                              <Button
                                variant="ghost"
                                size="sm"
                                className="text-rose-600 hover:bg-rose-50 hover:text-rose-700"
                                onClick={() => setRoleToRevoke(role)}
                              >
                                <Trash2 className="mr-1 h-4 w-4" />
                                Revoke
                              </Button>
                            </TableCell>
                          </TableRow>
                        ))
                      )}
                    </TableBody>
                  </Table>
                )}
                {!rolesLoading && !rolesError && (
                  <DataTablePagination
                    page={roleTable.page}
                    pageSize={roleTable.pageSize}
                    total={filteredRoles.length}
                    onPageChange={roleTable.setPage}
                  />
                )}
              </CardContent>
            </Card>
          )}

          {activeTab === "partners" && (
            <Card>
              <CardHeader>
                <CardTitle>Bank Partners</CardTitle>
                <CardDescription>Registered bank partners and MoMo routing metadata.</CardDescription>
              </CardHeader>
              <CardContent>
                <DataTableToolbar className="mb-4 rounded-lg border border-zinc-100 p-0">
                  <DataTableSearch
                    placeholder="Search partners..."
                    value={partnerTable.search}
                    onChange={partnerTable.setSearch}
                  />
                </DataTableToolbar>
                {partnersLoading ? (
                  <PageLoading message="Loading partners..." />
                ) : partnersError ? (
                  <PageError message={partnersError} onRetry={refetchPartners} />
                ) : (
                  <div className="space-y-4">
                    {visiblePartners.map((partner) => (
                      <div
                        key={partner.id}
                        className="flex flex-col gap-3 rounded-lg border border-zinc-200 p-4 sm:flex-row sm:items-center sm:justify-between"
                      >
                        <div className="flex items-center gap-4">
                          <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-blue-100 text-sm font-bold text-blue-700">
                            {partner.name.slice(0, 2).toUpperCase()}
                          </div>
                          <div>
                            <p className="text-sm font-semibold text-zinc-900">{partner.name}</p>
                            <p className="font-mono text-xs text-zinc-500">
                              {partner.momo_code ?? "No MoMo code"}
                            </p>
                          </div>
                        </div>
                        <Badge variant="outline">Read only</Badge>
                      </div>
                    ))}
                    {filteredPartners.length === 0 && (
                      <p className="py-8 text-center text-sm text-zinc-400">
                        No bank partners match this search.
                      </p>
                    )}
                    <DataTablePagination
                      page={partnerTable.page}
                      pageSize={partnerTable.pageSize}
                      total={filteredPartners.length}
                      onPageChange={partnerTable.setPage}
                    />
                  </div>
                )}
              </CardContent>
            </Card>
          )}

          {activeTab === "sms" && (
            <Card>
              <CardHeader>
                <CardTitle>SMS Pipeline Configuration</CardTitle>
                <CardDescription>MoMo SMS sender allowlist and parser-related configuration.</CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                {configLoading ? (
                  <PageLoading message="Loading SMS configuration..." />
                ) : configError ? (
                  <PageError message={configError} onRetry={refetchConfig} />
                ) : smsConfig.length === 0 ? (
                  <p className="py-8 text-center text-sm text-zinc-400">
                    No SMS or MoMo configuration rows are visible.
                  </p>
                ) : (
                  smsConfig.map((row) => {
                    const masked = maskConfigValue(row.key, row.value);
                    return (
                      <div key={row.key} className="space-y-1">
                        <label className="text-sm font-semibold text-zinc-900">{row.key}</label>
                        <Input value={masked.value} readOnly disabled />
                        {row.description && <p className="text-xs text-zinc-500">{row.description}</p>}
                      </div>
                    );
                  })
                )}
              </CardContent>
            </Card>
          )}
        </div>
      </div>

      <ConfirmDialog
        open={roleToRevoke !== null}
        tone="danger"
        title="Revoke admin role?"
        description="This removes this role assignment. The backend RPC enforces permissions and writes the audit record."
        confirmLabel="Revoke role"
        loading={revoking}
        onCancel={() => {
          if (!revoking) setRoleToRevoke(null);
        }}
        onConfirm={confirmRevokeRole}
      >
        {roleToRevoke && (
          <div className="rounded-xl bg-zinc-50 p-3 text-sm text-zinc-700">
            <div className="font-semibold text-zinc-950">
              {roleToRevoke.user_name || roleToRevoke.user_phone || roleToRevoke.user_id}
            </div>
            <div className="mt-1">
              {roleToRevoke.role} · {roleToRevoke.partner_name ?? "Global"}
            </div>
          </div>
        )}
      </ConfirmDialog>
    </div>
  );
}
