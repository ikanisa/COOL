import type { ReactNode } from "react";
import { Navigate, Outlet } from "react-router-dom";
import { useAuth } from "@/lib/auth";
import { ShieldAlert, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  firstAccessibleAdminPath,
  hasAdminAccess,
  hasAnyAdminAccess,
  type AdminAccessRequirement,
} from "@/lib/admin-access";

function AccessDenied({
  signOut,
  title = "Access Denied",
  message = "Your account does not have access to this admin area.",
}: {
  signOut?: () => Promise<void>;
  title?: string;
  message?: string;
}) {
  return (
    <div className="flex h-screen w-full items-center justify-center bg-[#F3F5F7]">
      <div className="max-w-md rounded-2xl bg-white p-8 shadow-lg text-center">
        <div className="mx-auto mb-6 flex h-16 w-16 items-center justify-center rounded-full bg-rose-100">
          <ShieldAlert className="h-8 w-8 text-rose-600" />
        </div>
        <h1 className="text-xl font-bold text-zinc-900 mb-2">{title}</h1>
        <p className="text-sm text-zinc-500 mb-6">{message}</p>
        {signOut && (
          <Button onClick={signOut} variant="outline" className="w-full">
            Sign Out
          </Button>
        )}
      </div>
    </div>
  );
}

export function AuthGuard() {
  const { user, adminAccess, loading, signOut } = useAuth();

  if (loading || (user && adminAccess === null)) {
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
  if (!hasAnyAdminAccess(adminAccess)) {
    return (
      <AccessDenied
        signOut={signOut}
        message="Your account does not have admin privileges. Contact a platform administrator to request access."
      />
    );
  }

  return <Outlet />;
}

export function RequireAdminAccess({
  access,
  children,
}: {
  access: AdminAccessRequirement;
  children: ReactNode;
}) {
  const { adminAccess } = useAuth();

  if (!hasAdminAccess(adminAccess, access)) {
    return (
      <AccessDenied message="Your admin role does not include permission for this page." />
    );
  }

  return <>{children}</>;
}

export function AdminIndexRoute({ children }: { children: ReactNode }) {
  const { adminAccess } = useAuth();
  const dashboardAccess: AdminAccessRequirement = { anyOf: ["view_analytics"] };

  if (!hasAdminAccess(adminAccess, dashboardAccess)) {
    return <Navigate to={firstAccessibleAdminPath(adminAccess)} replace />;
  }

  return <>{children}</>;
}
