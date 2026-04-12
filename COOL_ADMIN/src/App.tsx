import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { Suspense, lazy } from "react";
import { Loader2 } from "lucide-react";
import { AuthProvider } from "@/lib/auth";
import { AuthGuard } from "@/components/layout/AuthGuard";
import { AdminLayout } from "@/components/layout/AdminLayout";
import { AuthLayout } from "@/components/layout/AuthLayout";

/* ── Auth pages (small, load eagerly) ─────────────────────────────── */
import { Login } from "@/pages/auth/Login";
import { WhatsAppNumber } from "@/pages/auth/WhatsAppNumber";
import { WhatsAppOTP } from "@/pages/auth/WhatsAppOTP";

/* ── Admin pages (lazy loaded for code splitting) ─────────────────── */
const Dashboard = lazy(() => import("@/pages/Dashboard").then((m) => ({ default: m.Dashboard })));
const UsersList = lazy(() => import("@/pages/Users").then((m) => ({ default: m.UsersList })));
const CreateUser = lazy(() => import("@/pages/CreateUser").then((m) => ({ default: m.CreateUser })));
const MembersList = lazy(() => import("@/pages/Members").then((m) => ({ default: m.MembersList })));
const CreateMember = lazy(() => import("@/pages/CreateMember").then((m) => ({ default: m.CreateMember })));
const GroupsList = lazy(() => import("@/pages/Groups").then((m) => ({ default: m.GroupsList })));
const CreateGroup = lazy(() => import("@/pages/CreateGroup").then((m) => ({ default: m.CreateGroup })));
const Transactions = lazy(() => import("@/pages/Transactions").then((m) => ({ default: m.Transactions })));
const Loans = lazy(() => import("@/pages/Loans").then((m) => ({ default: m.Loans })));
const Reconciliation = lazy(() => import("@/pages/Reconciliation").then((m) => ({ default: m.Reconciliation })));
const BioPay = lazy(() => import("@/pages/BioPay").then((m) => ({ default: m.BioPay })));
const Approvals = lazy(() => import("@/pages/Approvals").then((m) => ({ default: m.Approvals })));
const Profile = lazy(() => import("@/pages/Profile").then((m) => ({ default: m.Profile })));
const Health = lazy(() => import("@/pages/Health").then((m) => ({ default: m.Health })));
const Settings = lazy(() => import("@/pages/Settings").then((m) => ({ default: m.Settings })));

/* ── Suspense fallback ────────────────────────────────────────────── */
function PageFallback() {
  return (
    <div className="flex h-96 items-center justify-center">
      <Loader2 className="h-8 w-8 animate-spin text-indigo-600" />
    </div>
  );
}

export default function App() {
  return (
    <AuthProvider>
      <BrowserRouter>
        <Suspense fallback={<PageFallback />}>
          <Routes>
            {/* Auth Routes — public, no guard */}
            <Route path="/auth" element={<AuthLayout />}>
              <Route index element={<Navigate to="/auth/login" replace />} />
              <Route path="login" element={<Login />} />
              <Route path="whatsapp-number" element={<WhatsAppNumber />} />
              <Route path="whatsapp-otp" element={<WhatsAppOTP />} />
            </Route>

            {/* Admin Routes — guarded + lazy loaded */}
            <Route element={<AuthGuard />}>
              <Route path="/" element={<AdminLayout />}>
                <Route index element={<Dashboard />} />
                <Route path="users" element={<UsersList />} />
                <Route path="users/create" element={<CreateUser />} />
                <Route path="members" element={<MembersList />} />
                <Route path="members/create" element={<CreateMember />} />
                <Route path="groups" element={<GroupsList />} />
                <Route path="groups/create" element={<CreateGroup />} />
                <Route path="transactions" element={<Transactions />} />
                <Route path="loans" element={<Loans />} />
                <Route path="reconciliation" element={<Reconciliation />} />
                <Route path="biopay" element={<BioPay />} />
                <Route path="approvals" element={<Approvals />} />
                <Route path="health" element={<Health />} />
                <Route path="profile" element={<Profile />} />
                <Route path="settings" element={<Settings />} />
              </Route>
            </Route>
          </Routes>
        </Suspense>
      </BrowserRouter>
    </AuthProvider>
  );
}
