import { useState } from "react";
import { Settings as SettingsIcon, Shield, Building2, Smartphone, Save, Loader2, RefreshCw, AlertTriangle, Trash2 } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
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

export function Settings() {
  const [activeTab, setActiveTab] = useState("app-config");

  const { data: config, loading: configLoading, error: configError, refetch: refetchConfig } = useAsyncData(async () => {
    const { data, error } = await supabase.from("app_config").select("key, value, description").order("key");
    if (error) throw new Error(error.message);
    return data as AppConfigRow[];
  });

  const { data: roles, loading: rolesLoading, error: rolesError, refetch: refetchRoles } = useAsyncData(async () => {
    const { data, error } = await supabase.rpc("list_admin_role_assignments", { p_role: null, p_active_only: true });
    if (error) throw new Error(error.message);
    return data as RoleAssignment[];
  });

  const { data: partners, loading: partnersLoading } = useAsyncData(async () => {
    const { data, error } = await supabase.from("partners").select("id, name, category, momo_code").eq("category", "bank").order("name");
    if (error) throw new Error(error.message);
    return data as Array<{ id: string; name: string; category: string; momo_code: string | null }>;
  });

  const handleRevokeRole = async (assignmentId: string) => {
    const { error } = await supabase.rpc("revoke_admin_role", { p_assignment_id: assignmentId });
    if (error) alert(error.message);
    else refetchRoles();
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
          <h1 className="text-2xl font-bold tracking-tight text-zinc-900">Platform Settings</h1>
          <p className="text-sm text-zinc-500 mt-1">Manage app configuration, admin roles, and partner integrations.</p>
        </div>
      </div>

      <div className="flex flex-col md:flex-row gap-6">
        <div className="w-full md:w-64 shrink-0 space-y-1">
          {tabs.map((t) => (
            <button
              key={t.id}
              onClick={() => setActiveTab(t.id)}
              className={`w-full flex items-center gap-3 px-3 py-2.5 text-sm font-medium rounded-lg transition-colors ${
                activeTab === t.id ? "bg-indigo-50 text-indigo-700" : "text-zinc-600 hover:bg-zinc-100"
              }`}
            >
              <t.icon className="h-4 w-4" /> {t.label}
            </button>
          ))}
        </div>

        <div className="flex-1 space-y-6">
          {/* ── App Config ── */}
          {activeTab === "app-config" && (
            <Card>
              <CardHeader>
                <CardTitle>Application Configuration</CardTitle>
                <CardDescription>Key-value configuration from app_config table.</CardDescription>
              </CardHeader>
              <CardContent>
                {configLoading ? (
                  <div className="flex justify-center py-8"><Loader2 className="h-6 w-6 animate-spin text-zinc-400" /></div>
                ) : configError ? (
                  <div className="text-center py-8"><AlertTriangle className="h-6 w-6 text-amber-500 mx-auto mb-2" /><p className="text-sm text-zinc-600">{configError}</p><Button onClick={refetchConfig} variant="outline" size="sm" className="mt-2"><RefreshCw className="h-4 w-4 mr-1" /> Retry</Button></div>
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
                          <TableCell className="font-mono text-xs text-zinc-700">{c.key}</TableCell>
                          <TableCell className="font-mono text-xs text-zinc-900 max-w-[200px] truncate">{c.value}</TableCell>
                          <TableCell className="text-xs text-zinc-500 max-w-[300px] truncate">{c.description ?? "—"}</TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                )}
              </CardContent>
            </Card>
          )}

          {/* ── Roles ── */}
          {activeTab === "roles" && (
            <Card>
              <CardHeader>
                <CardTitle>Active Role Assignments</CardTitle>
                <CardDescription>Database-backed RBAC from admin_role_assignments.</CardDescription>
              </CardHeader>
              <CardContent>
                {rolesLoading ? (
                  <div className="flex justify-center py-8"><Loader2 className="h-6 w-6 animate-spin text-zinc-400" /></div>
                ) : rolesError ? (
                  <div className="text-center py-8"><AlertTriangle className="h-6 w-6 text-amber-500 mx-auto mb-2" /><p className="text-sm text-zinc-600">{rolesError}</p><Button onClick={refetchRoles} variant="outline" size="sm" className="mt-2"><RefreshCw className="h-4 w-4 mr-1" /> Retry</Button></div>
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
                        <TableRow><TableCell colSpan={6} className="h-32 text-center text-zinc-400">No role assignments</TableCell></TableRow>
                      ) : (roles ?? []).map((r) => (
                        <TableRow key={r.id}>
                          <TableCell className="font-medium text-zinc-900">{r.user_name || "(Unknown)"}</TableCell>
                          <TableCell className="font-mono text-xs text-zinc-500">{r.user_phone || "—"}</TableCell>
                          <TableCell><Badge variant={r.role === "admin" ? "default" : "outline"} className={r.role === "admin" ? "bg-indigo-100 text-indigo-800" : ""}>{r.role}</Badge></TableCell>
                          <TableCell className="text-zinc-600">{r.partner_name ?? "Global"}</TableCell>
                          <TableCell className="text-sm text-zinc-500">{new Date(r.granted_at).toLocaleDateString()}</TableCell>
                          <TableCell className="text-right">
                            <Button variant="ghost" size="sm" className="text-rose-600 hover:text-rose-700 hover:bg-rose-50" onClick={() => handleRevokeRole(r.id)}>
                              <Trash2 className="h-4 w-4 mr-1" /> Revoke
                            </Button>
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                )}
              </CardContent>
            </Card>
          )}

          {/* ── Partners ── */}
          {activeTab === "partners" && (
            <Card>
              <CardHeader>
                <CardTitle>Bank Partners</CardTitle>
                <CardDescription>Registered bank partners and their MoMo codes.</CardDescription>
              </CardHeader>
              <CardContent>
                {partnersLoading ? (
                  <div className="flex justify-center py-8"><Loader2 className="h-6 w-6 animate-spin text-zinc-400" /></div>
                ) : (
                  <div className="space-y-4">
                    {(partners ?? []).map((p) => (
                      <div key={p.id} className="flex items-center justify-between p-4 border border-zinc-200 rounded-lg">
                        <div className="flex items-center gap-4">
                          <div className="h-10 w-10 rounded-lg bg-blue-100 flex items-center justify-center text-blue-700 font-bold text-sm">
                            {p.name.slice(0, 2).toUpperCase()}
                          </div>
                          <div>
                            <p className="text-sm font-medium text-zinc-900">{p.name}</p>
                            <p className="text-xs text-zinc-500 font-mono">{p.momo_code ?? "No MoMo code"}</p>
                          </div>
                        </div>
                        <Button variant="outline" size="sm">Edit</Button>
                      </div>
                    ))}
                    {(partners ?? []).length === 0 && (
                      <p className="text-sm text-zinc-400 text-center py-8">No bank partners configured</p>
                    )}
                  </div>
                )}
              </CardContent>
            </Card>
          )}

          {/* ── SMS Pipeline ── */}
          {activeTab === "sms" && (
            <Card>
              <CardHeader>
                <CardTitle>SMS Pipeline Configuration</CardTitle>
                <CardDescription>MoMo SMS sender allowlist and parsing configuration.</CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                <p className="text-sm text-zinc-500">SMS pipeline configuration is managed via the <code className="px-1 py-0.5 bg-zinc-100 rounded text-xs">momo_sms_sender_allowlist</code> table and app_config entries.</p>
                {config?.filter((c) => c.key.includes("sms") || c.key.includes("momo")).map((c) => (
                  <div key={c.key} className="space-y-1">
                    <label className="text-sm font-medium text-zinc-900">{c.key}</label>
                    <Input defaultValue={c.value} disabled />
                    {c.description && <p className="text-xs text-zinc-500">{c.description}</p>}
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
