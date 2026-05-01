import { useState } from "react";
import { NavLink, useNavigate } from "react-router-dom";
import { 
  LogOut,
  Menu,
  X
} from "lucide-react";
import { cn } from "@/lib/utils";
import { useAuth } from "@/lib/auth";
import { adminNavItems, hasAdminAccess } from "@/lib/admin-access";

export function Sidebar() {
  const navigate = useNavigate();
  const { adminAccess, signOut } = useAuth();
  const [mobileOpen, setMobileOpen] = useState(false);
  const accessibleNavItems = adminNavItems.filter((item) =>
    hasAdminAccess(adminAccess, item.access)
  );

  const handleLogout = async () => {
    await signOut();
    navigate("/auth/login");
  };

  const sidebarContent = (
    <>
      <div className="flex h-16 shrink-0 items-center justify-between px-6 border-b border-zinc-100">
        <div className="flex items-center gap-2 font-bold text-xl tracking-tight text-zinc-900">
          <img src="/logo.png" alt="COOL" className="h-8 w-8 rounded-lg" />
          COOL Admin
        </div>
        {/* Close button — mobile only */}
        <button
          onClick={() => setMobileOpen(false)}
          className="lg:hidden -mr-2 p-2 rounded-lg text-zinc-400 hover:bg-zinc-100 hover:text-zinc-600"
        >
          <X className="h-5 w-5" />
        </button>
      </div>

      <nav className="flex-1 overflow-y-auto p-4 space-y-1">
        <div className="text-xs font-semibold text-zinc-400 uppercase tracking-wider mb-4 mt-2 px-2">
          Platform Operations
        </div>
        {accessibleNavItems.map((item) => (
          <NavLink
            key={item.path}
            to={item.path}
            end={item.end ?? item.path === "/"}
            onClick={() => setMobileOpen(false)}
            className={({ isActive }) =>
              cn(
                "flex items-center justify-between rounded-lg px-3 py-2.5 text-sm font-medium transition-colors",
                isActive 
                  ? "bg-indigo-50 text-indigo-700" 
                  : "text-zinc-600 hover:bg-zinc-100 hover:text-zinc-900"
              )
            }
          >
            <div className="flex items-center gap-3">
              <item.icon className="h-5 w-5" />
              {item.label}
            </div>
          </NavLink>
        ))}
      </nav>

      <div className="p-4 border-t border-zinc-100">
        <button 
          onClick={handleLogout}
          className="flex w-full items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium text-zinc-600 transition-colors hover:bg-zinc-100 hover:text-zinc-900"
        >
          <LogOut className="h-5 w-5" />
          Sign Out
        </button>
      </div>
    </>
  );

  return (
    <>
      {/* Mobile toggle button — positioned inside header area to avoid overlap */}
      <button
        onClick={() => setMobileOpen(true)}
        aria-label="Open navigation menu"
        className="fixed top-[1.125rem] left-4 z-[60] lg:hidden p-2 rounded-lg bg-white shadow-md border border-zinc-200 text-zinc-600 hover:bg-zinc-50"
      >
        <Menu className="h-5 w-5" />
      </button>

      {/* Mobile overlay */}
      {mobileOpen && (
        <div
          className="fixed inset-0 z-[55] bg-black/30 backdrop-blur-sm lg:hidden"
          onClick={() => setMobileOpen(false)}
        />
      )}

      {/* Mobile drawer */}
      <aside
        className={cn(
          "fixed inset-y-0 left-0 z-[60] w-64 flex flex-col border-r border-zinc-200 bg-white transition-transform duration-300 lg:hidden",
          mobileOpen ? "translate-x-0" : "-translate-x-full"
        )}
      >
        {sidebarContent}
      </aside>

      {/* Desktop sidebar — always visible */}
      <aside className="hidden lg:fixed lg:inset-y-0 lg:left-0 lg:z-50 lg:w-64 lg:flex lg:flex-col lg:border-r lg:border-zinc-200 lg:bg-white">
        {sidebarContent}
      </aside>
    </>
  );
}
