import { Link } from "react-router-dom";
import { MessageCircle } from "lucide-react";
import { Button } from "@/components/ui/button";

export function Login() {
  return (
    <div className="bg-surface-low/60 backdrop-blur-[40px] rounded-[3rem] p-10 shadow-[0_20px_80px_-10px_rgba(13,10,39,0.8),inset_1px_1px_2px_rgba(255,255,255,0.05),inset_-1px_-1px_2px_rgba(0,0,0,0.4)] relative">
      <div className="text-center mb-10">
        <h2 className="text-3xl font-display font-bold text-white tracking-tighter mb-3">Welcome back</h2>
        <p className="text-primary/70 text-base font-sans">Sign in to access the platform</p>
      </div>

      <div className="space-y-6">
        <Link to="/auth/whatsapp-number" className="block">
          <Button 
            className="w-full h-16 bg-gradient-to-br from-[#25D366] to-[#1DA851] hover:from-[#20bd5a] hover:to-[#199447] text-white rounded-full font-sans font-bold text-lg transition-all shadow-[0_10px_40px_-10px_rgba(37,211,102,0.5),inset_2px_2px_4px_rgba(255,255,255,0.4),inset_-2px_-2px_4px_rgba(0,0,0,0.2)] hover:shadow-[0_15px_50px_-10px_rgba(37,211,102,0.6),inset_2px_2px_4px_rgba(255,255,255,0.5),inset_-2px_-2px_4px_rgba(0,0,0,0.2)] hover:-translate-y-1"
          >
            <MessageCircle className="mr-3 h-6 w-6" />
            Continue with WhatsApp
          </Button>
        </Link>
        
        <div className="relative py-6">
          <div className="absolute inset-0 flex items-center">
            <div className="w-full border-t border-white/5"></div>
          </div>
          <div className="relative flex justify-center text-xs">
            <span className="bg-surface-low px-4 py-1 rounded-full text-primary/50 font-label uppercase tracking-wider shadow-[inset_1px_1px_2px_rgba(0,0,0,0.2)]">Secure Admin Access</span>
          </div>
        </div>

        <p className="text-center text-sm text-primary/40 mt-8 font-sans leading-relaxed">
          By continuing, you agree to our Terms of Service and Privacy Policy.
        </p>
      </div>
    </div>
  );
}
