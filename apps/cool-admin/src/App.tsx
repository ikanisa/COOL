import { Suspense, lazy } from "react";
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { Loader2 } from "lucide-react";
import { AuthProvider } from "@/lib/auth";
import { AuthGuard } from "@/components/layout/AuthGuard";
import { AdminLayout } from "@/components/layout/AdminLayout";
import { AuthLayout } from "@/components/layout/AuthLayout";

const Login = lazy(() =>
  import("@/pages/auth/Login").then((module) => ({ default: module.Login })),
);
const WhatsAppNumber = lazy(() =>
  import("@/pages/auth/WhatsAppNumber").then((module) => ({
    default: module.WhatsAppNumber,
  })),
);
const WhatsAppOTP = lazy(() =>
  import("@/pages/auth/WhatsAppOTP").then((module) => ({
    default: module.WhatsAppOTP,
  })),
);
const Dashboard = lazy(() =>
  import("@/pages/Dashboard").then((module) => ({ default: module.Dashboard })),
);
const UsersList = lazy(() =>
  import("@/pages/Users").then((module) => ({ default: module.UsersList })),
);
const CreateUser = lazy(() =>
  import("@/pages/CreateUser").then((module) => ({ default: module.CreateUser })),
);
const MembersList = lazy(() =>
  import("@/pages/Members").then((module) => ({ default: module.MembersList })),
);
const CreateMember = lazy(() =>
  import("@/pages/CreateMember").then((module) => ({
    default: module.CreateMember,
  })),
);
const GroupsList = lazy(() =>
  import("@/pages/Groups").then((module) => ({ default: module.GroupsList })),
);
const CreateGroup = lazy(() =>
  import("@/pages/CreateGroup").then((module) => ({ default: module.CreateGroup })),
);
const Transactions = lazy(() =>
  import("@/pages/Transactions").then((module) => ({
    default: module.Transactions,
  })),
);
const Loans = lazy(() =>
  import("@/pages/Loans").then((module) => ({ default: module.Loans })),
);
const Reconciliation = lazy(() =>
  import("@/pages/Reconciliation").then((module) => ({
    default: module.Reconciliation,
  })),
);
const BioPay = lazy(() =>
  import("@/pages/BioPay").then((module) => ({ default: module.BioPay })),
);
const Approvals = lazy(() =>
  import("@/pages/Approvals").then((module) => ({ default: module.Approvals })),
);
const Profile = lazy(() =>
  import("@/pages/Profile").then((module) => ({ default: module.Profile })),
);
const Health = lazy(() =>
  import("@/pages/Health").then((module) => ({ default: module.Health })),
);
const Settings = lazy(() =>
  import("@/pages/Settings").then((module) => ({ default: module.Settings })),
);

function RouteFallback() {
  return (
    <div className="flex h-screen w-full items-center justify-center bg-[#F3F5F7]">
      <div className="flex flex-col items-center gap-4">
        <Loader2 className="h-8 w-8 animate-spin text-indigo-600" />
        <p className="text-sm font-medium text-zinc-500">Loading workspace…</p>
      </div>
    </div>
  );
}

export default function App() {
  return (
    <AuthProvider>
      <BrowserRouter>
        <Suspense fallback={<RouteFallback />}>
          <Routes>
            <Route path="/auth" element={<AuthLayout />}>
              <Route index element={<Navigate to="/auth/login" replace />} />
              <Route path="login" element={<Login />} />
              <Route path="whatsapp-number" element={<WhatsAppNumber />} />
              <Route path="whatsapp-otp" element={<WhatsAppOTP />} />
            </Route>

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
