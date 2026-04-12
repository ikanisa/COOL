import { NavLink, useNavigate } from "react-router-dom";
import { 
  LayoutDashboard, 
  User,
  Users,
  Layers,
  Wallet,
  Banknote,
  ShieldAlert, 
  Activity, 
  Settings,
  LogOut,
  FileText,
  Fingerprint
} from "lucide-react";
import { cn } from "@/lib/utils";

const navItems = [
  { icon: LayoutDashboard, label: "Dashboard", path: "/" },
  { icon: User, label: "User Management", path: "/users" },
  { icon: Users, label: "Members", path: "/members" },
  { icon: Layers, label: "Groups", path: "/groups" },
  { icon: Wallet, label: "Transactions", path: "/transactions" },
  { icon: Banknote, label: "Loans", path: "/loans" },
  { icon: FileText, label: "Allocation", path: "/reconciliation", badge: "24" },
  { icon: Fingerprint, label: "BioPay", path: "/biopay" },
  { icon: ShieldAlert, label: "Approvals", path: "/approvals", badge: "12" },
  { icon: Activity, label: "System Health", path: "/health" },
  { icon: Settings, label: "Settings", path: "/settings" },
];

export function Sidebar() {
  const navigate = useNavigate();

  const handleLogout = () => {
    navigate("/auth/login");
  };

  return (
    <aside className="fixed inset-y-0 left-0 z-50 w-64 flex flex-col border-r border-zinc-200 bg-white">
      <div className="flex h-16 shrink-0 items-center px-6 border-b border-zinc-100">
        <div className="flex items-center gap-2 font-bold text-xl tracking-tight text-zinc-900">
          <img src="/icon-192.png" alt="COOL" className="h-8 w-8 rounded-lg" />
          COOL Admin
        </div>
      </div>

      <nav className="flex-1 overflow-y-auto p-4 space-y-1">
        <div className="text-xs font-semibold text-zinc-400 uppercase tracking-wider mb-4 mt-2 px-2">
          Platform Operations
        </div>
        {navItems.map((item) => (
          <NavLink
            key={item.path}
            to={item.path}
            end={item.path === "/"}
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
            {item.badge && (
              <span className="flex h-5 items-center justify-center rounded-full bg-rose-100 px-2 text-[10px] font-bold text-rose-700">
                {item.badge}
              </span>
            )}
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
    </aside>
  );
}
