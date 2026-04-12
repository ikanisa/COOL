import { useState } from "react";
import {
  Settings as SettingsIcon,
  Shield,
  Building2,
  Smartphone,
  Loader2,
  RefreshCw,
  AlertTriangle,
  Trash2,
  Search,
  Plus,
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
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { supabase } from "@/lib/supabase";
import { useAsyncData } from "@/lib/hooks";

interface RoleAssignment {
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

interface AppConfigRow {
  key: string;
  value: string;
  description: string | null;
}

interface PartnerRow {
  id: string;
  name: string;
  category: string;
  slug: string | null;
  momo_code: string | null;
}

interface UserOption {
  id: string;
  full_name: string;
  phone: string;
}

export function Settings() {
  const [activeTab, setActiveTab] = useState("app-config");
  const [roleForm, setRoleForm] = useState({
    search: "",
    selectedUser: null as UserOption | null,
    role: "admin",
    partnerId: "",
    notes: "",
  });
  const [roleSubmitError, setRoleSubmitError] = useState<string | null>(null);
  const [roleSubmitting, setRoleSubmitting] = useState(false);
  const [revokingId, setRevokingId] = useState<string | null>(null);

  const {
    data: config,
    loading: configLoading,
    error: configError,
    refetch: refetchConfig,
  } = useAsyncData(async () => {
    const { data, error } = await supabase
      .from("app_config")
      .select("key, value, description")
      .order("key");
    if (error) throw new Error(error.message);
    return data as AppConfigRow[];
  });

  const {
    data: roles,
    loading: rolesLoading,
    error: rolesError,
    refetch: refetchRoles,
  } = useAsyncData(async () => {
    const { data, error } = await supabase.rpc("list_admin_role_assignments", {
      p_role: null,
      p_active_only: true,
    });
    if (error) throw new Error(error.message);
    return data as RoleAssignment[];
  });

  const { data: partners, loading: partnersLoading } = useAsyncData(async () => {
    const { data, error } = await supabase
      .from("partners")
      .select("id, name, category, slug, momo_code")
      .order("name");
    if (error) throw new Error(error.message);
    return data as PartnerRow[];
  });

  const { data: userSearchResults, loading: userSearchLoading } = useAsyncData(
    async () => {
      if (roleForm.search.trim().length < 2) {
        return [];
      }
      const query = roleForm.search.trim();
      const { data, error } = await supabase
        .from("users")
        .select("id, full_name, phone")
        .or(`full_name.ilike.%${query}%,phone.ilike.%${query}%`)
        .order("full_name")
        .limit(8);
      if (error) throw new Error(error.message);
      return (data ?? []) as UserOption[];
    },
    [roleForm.search],
  );

  const updateRoleForm = (
    field: keyof typeof roleForm,
    value: string | UserOption | null,
  ) => {
    setRoleSubmitError(null);
    setRoleForm((prev) => ({ ...prev, [field]: value }));
  };

  const visiblePartnerOptions = (partners ?? []).filter((partner) => {
    if (roleForm.role === "admin") {
      return false;
    }
    if (roleForm.role === "bank") {
      return partner.category === "bank";
    }
    return partner.slug === "rayon-sports";
  });

  const resetRoleForm = () => {
    setRoleForm({
      search: "",
      selectedUser: null,
      role: "admin",
      partnerId: "",
      notes: "",
    });
    setRoleSubmitError(null);
  };

  const handleAssignRole = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!roleForm.selectedUser) {
      setRoleSubmitError("Select a user before assigning a role.");
      return;
    }
    if (roleForm.role !== "admin" && !roleForm.partnerId) {
      setRoleSubmitError("Select the partner scope for this role.");
      return;
    }

    setRoleSubmitting(true);
    setRoleSubmitError(null);
    try {
      const { error } = await supabase.rpc("assign_admin_role", {
        p_target_user_id: roleForm.selectedUser.id,
        p_role: roleForm.role,
        p_partner_scope_id:
          roleForm.role === "admin" ? null : roleForm.partnerId,
        p_notes: roleForm.notes.trim() || null,
      });
      if (error) throw new Error(error.message);
      resetRoleForm();
      await refetchRoles();
    } catch (err) {
      setRoleSubmitError(
        err instanceof Error ? err.message : "Failed to assign role.",
      );
    } finally {
      setRoleSubmitting(false);
    }
  };

  const handleRevokeRole = async (assignmentId: string) => {
    setRevokingId(assignmentId);
    try {
      const { error } = await supabase.rpc("revoke_admin_role", {
        p_assignment_id: assignmentId,
      });
      if (error) throw new Error(error.message);
      await refetchRoles();
    } catch (err) {
      alert(err instanceof Error ? err.message : "Failed to revoke role.");
    } finally {
      setRevokingId(null);
    }
  };

  const tabs = [
    { id: "app-config", label: "App Configuration", icon: SettingsIcon },
    { id: "roles", label: "Admin Roles", icon: Shield },
    { id: "partners", label: "Bank Partners", icon: Building2 },
    { id: "sms", label: "SMS Pipeline", icon: Smartphone },
  ];

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-zinc-900">
            Platform Settings
          </h1>
          <p className="text-sm text-zinc-500 mt-1">
            Manage app configuration, admin roles, and partner integrations.
          </p>
        </div>
      </div>

      <div className="flex flex-col md:flex-row gap-6">
        <div className="w-full md:w-64 shrink-0 space-y-1">
          {tabs.map((t) => (
            <button
              key={t.id}
              onClick={() => setActiveTab(t.id)}
              className={`w-full flex items-center gap-3 px-3 py-2.5 text-sm font-medium rounded-lg transition-colors ${
                activeTab === t.id
                  ? "bg-indigo-50 text-indigo-700"
                  : "text-zinc-600 hover:bg-zinc-100"
              }`}
            >
              <t.icon className="h-4 w-4" /> {t.label}
            </button>
          ))}
        </div>

        <div className="flex-1 space-y-6">
          {activeTab === "app-config" && (
            <Card>
              <CardHeader>
                <CardTitle>Application Configuration</CardTitle>
                <CardDescription>
                  Key-value configuration from app_config table.
                </CardDescription>
              </CardHeader>
              <CardContent>
                {configLoading ? (
                  <div className="flex justify-center py-8">
                    <Loader2 className="h-6 w-6 animate-spin text-zinc-400" />
                  </div>
                ) : configError ? (
                  <div className="text-center py-8">
                    <AlertTriangle className="h-6 w-6 text-amber-500 mx-auto mb-2" />
                    <p className="text-sm text-zinc-600">{configError}</p>
                    <Button
                      onClick={refetchConfig}
                      variant="outline"
                      size="sm"
                      className="mt-2"
                    >
                      <RefreshCw className="h-4 w-4 mr-1" /> Retry
                    </Button>
                  </div>
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
                      {(config ?? []).map((c) => (
                        <TableRow key={c.key}>
                          <TableCell className="font-mono text-xs text-zinc-700">
                            {c.key}
                          </TableCell>
                          <TableCell className="font-mono text-xs text-zinc-900 max-w-[200px] truncate">
                            {c.value}
                          </TableCell>
                          <TableCell className="text-xs text-zinc-500 max-w-[300px] truncate">
                            {c.description ?? "—"}
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                )}
              </CardContent>
            </Card>
          )}

          {activeTab === "roles" && (
            <>
              <Card>
                <CardHeader>
                  <CardTitle>Assign Admin Role</CardTitle>
                  <CardDescription>
                    Grant platform or scoped workspace access through the RBAC
                    contract.
                  </CardDescription>
                </CardHeader>
                <CardContent>
                  <form onSubmit={handleAssignRole} className="space-y-4">
                    <div className="space-y-2">
                      <label className="text-sm font-medium text-zinc-900">
                        Search User
                      </label>
                      <div className="relative">
                        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-zinc-400" />
                        <Input
                          className="pl-9"
                          placeholder="Search name or phone..."
                          value={roleForm.search}
                          onChange={(e) => {
                            updateRoleForm("search", e.target.value);
                            updateRoleForm("selectedUser", null);
                          }}
                          disabled={roleSubmitting}
                        />
                      </div>
                      {userSearchLoading && (
                        <p className="text-xs text-zinc-500">Searching users…</p>
                      )}
                      {(userSearchResults ?? []).length > 0 &&
                        !roleForm.selectedUser && (
                          <div className="border border-zinc-200 rounded-lg divide-y divide-zinc-100 max-h-48 overflow-y-auto">
                            {(userSearchResults ?? []).map((user) => (
                              <button
                                key={user.id}
                                type="button"
                                onClick={() => {
                                  updateRoleForm("selectedUser", user);
                                  updateRoleForm(
                                    "search",
                                    `${user.full_name} (${user.phone})`,
                                  );
                                }}
                                className="w-full flex items-center justify-between p-3 hover:bg-zinc-50 text-left"
                              >
                                <span className="text-sm font-medium text-zinc-900">
                                  {user.full_name || "(Unnamed)"}
                                </span>
                                <span className="font-mono text-xs text-zinc-500">
                                  {user.phone}
                                </span>
                              </button>
                            ))}
                          </div>
                        )}
                      {roleForm.selectedUser && (
                        <div className="rounded-lg bg-emerald-50 px-3 py-2 text-sm text-emerald-700">
                          Selected: {roleForm.selectedUser.full_name} (
                          {roleForm.selectedUser.phone})
                        </div>
                      )}
                    </div>

                    <div className="grid gap-4 md:grid-cols-2">
                      <div className="space-y-2">
                        <label className="text-sm font-medium text-zinc-900">
                          Role
                        </label>
                        <select
                          value={roleForm.role}
                          onChange={(e) => {
                            updateRoleForm("role", e.target.value);
                            updateRoleForm("partnerId", "");
                          }}
                          disabled={roleSubmitting}
                          className="w-full h-10 px-3 rounded-lg border border-zinc-200 bg-white text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
                        >
                          <option value="admin">Platform admin</option>
                          <option value="bank">Bank admin</option>
                          <option value="rayon_sport">Rayon Sports admin</option>
                        </select>
                      </div>
                      {roleForm.role !== "admin" && (
                        <div className="space-y-2">
                          <label className="text-sm font-medium text-zinc-900">
                            Partner Scope
                          </label>
                          <select
                            value={roleForm.partnerId}
                            onChange={(e) =>
                              updateRoleForm("partnerId", e.target.value)
                            }
                            disabled={roleSubmitting}
                            className="w-full h-10 px-3 rounded-lg border border-zinc-200 bg-white text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
                          >
                            <option value="">Select partner…</option>
                            {visiblePartnerOptions.map((partner) => (
                              <option key={partner.id} value={partner.id}>
                                {partner.name}
                              </option>
                            ))}
                          </select>
                        </div>
                      )}
                    </div>

                    <div className="space-y-2">
                      <label className="text-sm font-medium text-zinc-900">
                        Notes
                      </label>
                      <Input
                        value={roleForm.notes}
                        onChange={(e) => updateRoleForm("notes", e.target.value)}
                        placeholder="Optional grant note..."
                        disabled={roleSubmitting}
                      />
                    </div>

                    {roleSubmitError && (
                      <p className="text-sm text-rose-600 font-medium">
                        {roleSubmitError}
                      </p>
                    )}

                    <div className="flex justify-end">
                      <Button
                        type="submit"
                        disabled={roleSubmitting}
                        className="bg-indigo-600 hover:bg-indigo-700 text-white"
                      >
                        {roleSubmitting ? (
                          <>
                            <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                            Assigning…
                          </>
                        ) : (
                          <>
                            <Plus className="h-4 w-4 mr-2" />
                            Assign Role
                          </>
                        )}
                      </Button>
                    </div>
                  </form>
                </CardContent>
              </Card>

              <Card>
                <CardHeader>
                  <CardTitle>Active Role Assignments</CardTitle>
                  <CardDescription>
                    Database-backed RBAC from admin_role_assignments.
                  </CardDescription>
                </CardHeader>
                <CardContent>
                  {rolesLoading ? (
                    <div className="flex justify-center py-8">
                      <Loader2 className="h-6 w-6 animate-spin text-zinc-400" />
                    </div>
                  ) : rolesError ? (
                    <div className="text-center py-8">
                      <AlertTriangle className="h-6 w-6 text-amber-500 mx-auto mb-2" />
                      <p className="text-sm text-zinc-600">{rolesError}</p>
                      <Button
                        onClick={refetchRoles}
                        variant="outline"
                        size="sm"
                        className="mt-2"
                      >
                        <RefreshCw className="h-4 w-4 mr-1" /> Retry
                      </Button>
                    </div>
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
                        {(roles ?? []).length === 0 ? (
                          <TableRow>
                            <TableCell
                              colSpan={6}
                              className="h-32 text-center text-zinc-400"
                            >
                              No role assignments
                            </TableCell>
                          </TableRow>
                        ) : (
                          (roles ?? []).map((r) => (
                            <TableRow key={r.id}>
                              <TableCell className="font-medium text-zinc-900">
                                {r.user_name || "(Unknown)"}
                              </TableCell>
                              <TableCell className="font-mono text-xs text-zinc-500">
                                {r.user_phone || "—"}
                              </TableCell>
                              <TableCell>
                                <Badge
                                  variant={
                                    r.role === "admin" ? "default" : "outline"
                                  }
                                  className={
                                    r.role === "admin"
                                      ? "bg-indigo-100 text-indigo-800"
                                      : ""
                                  }
                                >
                                  {r.role}
                                </Badge>
                              </TableCell>
                              <TableCell className="text-zinc-600">
                                {r.partner_name ?? "Global"}
                              </TableCell>
                              <TableCell className="text-sm text-zinc-500">
                                {new Date(r.granted_at).toLocaleDateString()}
                              </TableCell>
                              <TableCell className="text-right">
                                <Button
                                  variant="ghost"
                                  size="sm"
                                  className="text-rose-600 hover:text-rose-700 hover:bg-rose-50"
                                  onClick={() => handleRevokeRole(r.id)}
                                  disabled={revokingId === r.id}
                                >
                                  {revokingId === r.id ? (
                                    <Loader2 className="h-4 w-4 mr-1 animate-spin" />
                                  ) : (
                                    <Trash2 className="h-4 w-4 mr-1" />
                                  )}
                                  Revoke
                                </Button>
                              </TableCell>
                            </TableRow>
                          ))
                        )}
                      </TableBody>
                    </Table>
                  )}
                </CardContent>
              </Card>
            </>
          )}

          {activeTab === "partners" && (
            <Card>
              <CardHeader>
                <CardTitle>Bank Partners</CardTitle>
                <CardDescription>
                  Registered bank partners and their MoMo codes.
                </CardDescription>
              </CardHeader>
              <CardContent>
                {partnersLoading ? (
                  <div className="flex justify-center py-8">
                    <Loader2 className="h-6 w-6 animate-spin text-zinc-400" />
                  </div>
                ) : (
                  <div className="space-y-4">
                    {(partners ?? [])
                      .filter((partner) => partner.category === "bank")
                      .map((p) => (
                        <div
                          key={p.id}
                          className="flex items-center justify-between p-4 border border-zinc-200 rounded-lg"
                        >
                          <div className="flex items-center gap-4">
                            <div className="h-10 w-10 rounded-lg bg-blue-100 flex items-center justify-center text-blue-700 font-bold text-sm">
                              {p.name.slice(0, 2).toUpperCase()}
                            </div>
                            <div>
                              <p className="text-sm font-medium text-zinc-900">
                                {p.name}
                              </p>
                              <p className="text-xs text-zinc-500 font-mono">
                                {p.momo_code ?? "No MoMo code"}
                              </p>
                            </div>
                          </div>
                          <Button variant="outline" size="sm">
                            Edit
                          </Button>
                        </div>
                      ))}
                    {(partners ?? []).filter((partner) => partner.category === "bank")
                      .length === 0 && (
                      <p className="text-sm text-zinc-400 text-center py-8">
                        No bank partners configured
                      </p>
                    )}
                  </div>
                )}
              </CardContent>
            </Card>
          )}

          {activeTab === "sms" && (
            <Card>
              <CardHeader>
                <CardTitle>SMS Pipeline Configuration</CardTitle>
                <CardDescription>
                  MoMo SMS sender allowlist and parsing configuration.
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                <p className="text-sm text-zinc-500">
                  SMS pipeline configuration is managed via the{" "}
                  <code className="px-1 py-0.5 bg-zinc-100 rounded text-xs">
                    momo_sms_sender_allowlist
                  </code>{" "}
                  table and app_config entries.
                </p>
                {config
                  ?.filter((c) => c.key.includes("sms") || c.key.includes("momo"))
                  .map((c) => (
                    <div key={c.key} className="space-y-1">
                      <label className="text-sm font-medium text-zinc-900">
                        {c.key}
                      </label>
                      <Input defaultValue={c.value} disabled />
                      {c.description && (
                        <p className="text-xs text-zinc-500">
                          {c.description}
                        </p>
                      )}
                    </div>
                  ))}
              </CardContent>
            </Card>
          )}
        </div>
      </div>
    </div>
  );
}
