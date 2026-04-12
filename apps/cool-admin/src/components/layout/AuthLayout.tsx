import { Outlet } from "react-router-dom";

export function AuthLayout() {
  return (
    <div className="min-h-screen bg-surface-lowest flex flex-col items-center justify-center p-6 relative overflow-hidden">
      {/* Ambient background glows */}
      <div className="absolute top-[-20%] left-[-10%] w-[60%] h-[60%] rounded-full bg-primary-container opacity-20 blur-[120px] pointer-events-none" />
      <div className="absolute bottom-[-20%] right-[-10%] w-[60%] h-[60%] rounded-full bg-primary opacity-10 blur-[120px] pointer-events-none" />
      
      <div className="w-full max-w-md z-10 relative">
        <div className="flex flex-col items-center mb-12">
          <img src="/icon-192.png" alt="COOL" className="h-16 w-16 rounded-[1.5rem] mb-6 shadow-[0_10px_40px_-10px_rgba(135,129,255,0.6)]" />
          <h1 className="text-4xl md:text-5xl font-bold text-white tracking-tighter font-display text-center leading-tight">
            COOL Admin
          </h1>
          <p className="text-primary/70 text-sm md:text-base mt-3 font-medium font-label tracking-wide uppercase">
            Operational Control System
          </p>
        </div>
        
        <Outlet />
      </div>
    </div>
  );
}
