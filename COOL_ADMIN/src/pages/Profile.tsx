import { Mail, Phone, Shield, Clock, Smartphone, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { useAuth } from "@/lib/auth";

export function Profile() {
  const { user, adminAccess, loading } = useAuth();

  if (loading || !user) {
    return <div className="flex h-96 items-center justify-center"><Loader2 className="h-8 w-8 animate-spin text-indigo-600" /></div>;
  }

  const fullName = user.user_metadata?.full_name || user.email || user.phone || "Admin";
  const initials = fullName.split(" ").map((n: string) => n[0]).join("").slice(0, 2).toUpperCase();
  const phone = user.phone || user.user_metadata?.phone || "Not set";
  const email = user.email || "Not set";
  const roles = adminAccess?.role_assignments ?? [];

  return (
    <div className="max-w-6xl mx-auto space-y-8">
      <div>
        <h1 className="text-4xl font-display font-bold text-zinc-900 tracking-tight">Admin Profile</h1>
        <p className="text-zinc-500 font-sans mt-2">Your account information and security settings.</p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        {/* Left Column: Profile Summary */}
        <div className="space-y-8">
          <div className="bg-white rounded-[2rem] p-8 shadow-[0_20px_60px_-15px_rgba(0,0,0,0.05)]">
            <div className="flex flex-col items-center text-center">
              <div className="h-24 w-24 rounded-[1.5rem] bg-indigo-100 flex items-center justify-center mb-6 shadow-inner">
                <span className="text-3xl font-display font-bold text-indigo-600">{initials}</span>
              </div>
              <h2 className="text-2xl font-display font-bold text-zinc-900">{fullName}</h2>
              <div className="mt-3 flex flex-wrap gap-2 justify-center">
                {adminAccess?.has_platform_access && (
                  <Badge className="bg-indigo-50 text-indigo-700">Platform Admin</Badge>
                )}
                {adminAccess?.has_bank_access && !adminAccess?.has_platform_access && (
                  <Badge className="bg-emerald-50 text-emerald-700">Bank Admin</Badge>
                )}
              </div>
            </div>

            <div className="mt-10 space-y-6">
              <div className="flex items-center gap-4">
                <div className="h-12 w-12 rounded-full bg-zinc-50 flex items-center justify-center shrink-0">
                  <Mail className="h-5 w-5 text-zinc-400" />
                </div>
                <div>
                  <p className="text-xs font-label font-semibold text-zinc-400 uppercase tracking-wider">Email</p>
                  <p className="text-sm font-sans font-medium text-zinc-900 mt-0.5">{email}</p>
                </div>
              </div>
              <div className="flex items-center gap-4">
                <div className="h-12 w-12 rounded-full bg-zinc-50 flex items-center justify-center shrink-0">
                  <Phone className="h-5 w-5 text-zinc-400" />
                </div>
                <div>
                  <p className="text-xs font-label font-semibold text-zinc-400 uppercase tracking-wider">Phone</p>
                  <p className="text-sm font-sans font-medium text-zinc-900 mt-0.5">{phone}</p>
                </div>
              </div>
            </div>

            <div className="mt-10 pt-8 border-t border-zinc-100">
              <p className="text-xs text-zinc-400 text-center">
                Account created: {new Date(user.created_at).toLocaleDateString()}
              </p>
            </div>
          </div>
        </div>

        {/* Right Column */}
        <div className="lg:col-span-2 space-y-8">
          {/* Role Assignments */}
          <div className="bg-white rounded-[2rem] p-8 shadow-[0_20px_60px_-15px_rgba(0,0,0,0.05)]">
            <div className="flex items-center gap-4 mb-8">
              <div className="h-12 w-12 rounded-full bg-indigo-50 flex items-center justify-center">
                <Shield className="h-6 w-6 text-indigo-600" />
              </div>
              <h3 className="text-2xl font-display font-bold text-zinc-900">Role Assignments</h3>
            </div>

            {roles.length === 0 ? (
              <p className="text-sm text-zinc-400 text-center py-6">No role assignments found.</p>
            ) : (
              <div className="space-y-4">
                {roles.map((r) => (
                  <div key={r.id} className="flex items-center justify-between p-5 rounded-[1.5rem] bg-zinc-50">
                    <div className="flex items-center gap-5">
                      <div className="h-12 w-12 rounded-full bg-white flex items-center justify-center shadow-sm">
                        <Shield className="h-6 w-6 text-indigo-600" />
                      </div>
                      <div>
                        <p className="text-base font-sans font-bold text-zinc-900 capitalize">{r.role} Role</p>
                        <p className="text-sm font-sans text-zinc-500 mt-0.5">
                          {r.partner_name ? `Scoped to ${r.partner_name}` : "Global platform access"}
                        </p>
                      </div>
                    </div>
                    <Badge className="bg-emerald-100 text-emerald-700">Active</Badge>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Capabilities */}
          <div className="bg-white rounded-[2rem] p-8 shadow-[0_20px_60px_-15px_rgba(0,0,0,0.05)]">
            <div className="flex items-center gap-4 mb-8">
              <div className="h-12 w-12 rounded-full bg-indigo-50 flex items-center justify-center">
                <Clock className="h-6 w-6 text-indigo-600" />
              </div>
              <h3 className="text-2xl font-display font-bold text-zinc-900">Capabilities</h3>
            </div>

            <div className="grid grid-cols-2 gap-4">
              {adminAccess?.capabilities &&
                Object.entries(adminAccess.capabilities).map(([key, value]) => (
                  <div key={key} className="flex items-center justify-between p-3 rounded-lg bg-zinc-50">
                    <span className="text-sm text-zinc-700 capitalize">{key.replace(/_/g, " ")}</span>
                    <Badge variant={value ? "success" : "outline"}>
                      {value ? "Yes" : "No"}
                    </Badge>
                  </div>
                ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
