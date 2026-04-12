import { Navigate, Outlet } from "react-router-dom";
import { useAuth } from "@/lib/auth";
import { ShieldAlert, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";

export function AuthGuard() {
  const { user, adminAccess, loading, signOut } = useAuth();

  if (loading) {
    return (
      <div className="flex h-screen w-full items-center justify-center bg-[#F3F5F7]">
        <div className="flex flex-col items-center gap-4">
          <Loader2 className="h-8 w-8 animate-spin text-indigo-600" />
          <p className="text-sm text-zinc-500 font-medium">Verifying access…</p>
        </div>
      </div>
    );
  }

  // Not authenticated → kick to login
  if (!user) {
    return <Navigate to="/auth/login" replace />;
  }

  // Authenticated but no admin access
  if (
    adminAccess &&
    !adminAccess.has_platform_access &&
    !adminAccess.has_bank_access
  ) {
    return (
      <div className="flex h-screen w-full items-center justify-center bg-[#F3F5F7]">
        <div className="max-w-md rounded-2xl bg-white p-8 shadow-lg text-center">
          <div className="mx-auto mb-6 flex h-16 w-16 items-center justify-center rounded-full bg-rose-100">
            <ShieldAlert className="h-8 w-8 text-rose-600" />
          </div>
          <h1 className="text-xl font-bold text-zinc-900 mb-2">
            Access Denied
          </h1>
          <p className="text-sm text-zinc-500 mb-6">
            Your account does not have admin privileges. Contact a platform
            administrator to request access.
          </p>
          <Button
            onClick={signOut}
            variant="outline"
            className="w-full"
          >
            Sign Out
          </Button>
        </div>
      </div>
    );
  }

  return <Outlet />;
}
