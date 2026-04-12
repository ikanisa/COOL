import { Outlet } from "react-router-dom";
import { Sidebar } from "./Sidebar";
import { Header } from "./Header";

export function AdminLayout() {
  return (
    <div className="min-h-screen bg-[#F3F5F7]">
      <Sidebar />
      <div className="lg:pl-64 flex flex-col min-h-screen">
        <Header />
        <main className="flex-1 p-4 sm:p-6 lg:p-8">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
