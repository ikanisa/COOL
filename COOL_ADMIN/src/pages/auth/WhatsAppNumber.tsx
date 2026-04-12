import React, { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { ArrowLeft, ArrowRight, Phone } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

export function WhatsAppNumber() {
  const [number, setNumber] = useState("");
  const navigate = useNavigate();

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (number.length > 5) {
      navigate("/auth/whatsapp-otp");
    }
  };

  return (
    <div className="bg-surface-low/60 backdrop-blur-[40px] rounded-[3rem] p-10 shadow-[0_20px_80px_-10px_rgba(13,10,39,0.8),inset_1px_1px_2px_rgba(255,255,255,0.05),inset_-1px_-1px_2px_rgba(0,0,0,0.4)] relative">
      <div className="mb-10">
        <Link to="/auth/login" className="inline-flex items-center text-primary/60 hover:text-white transition-colors mb-8 text-sm font-label font-medium uppercase tracking-wider">
          <ArrowLeft className="mr-2 h-4 w-4" />
          Back
        </Link>
        <h2 className="text-3xl font-display font-bold text-white tracking-tighter mb-3">Enter your number</h2>
        <p className="text-primary/70 text-base font-sans leading-relaxed">We'll send a secure code to your WhatsApp to verify your identity.</p>
      </div>

      <form onSubmit={handleSubmit} className="space-y-8">
        <div className="space-y-3">
          <label className="text-sm font-label font-medium text-primary/80 uppercase tracking-wider">WhatsApp Number</label>
          <div className="relative flex items-center">
            <div className="absolute left-5 flex items-center gap-2 text-primary/60 font-mono text-lg">
              <Phone className="h-5 w-5" />
              <span>+250</span>
            </div>
            <Input 
              type="tel"
              placeholder="788 123 456"
              value={number}
              onChange={(e) => setNumber(e.target.value)}
              className="h-16 pl-28 bg-surface-lowest border-transparent text-white placeholder:text-primary/30 focus:border-electric-violet/40 focus:ring-1 focus:ring-electric-violet/40 rounded-[1.5rem] font-mono text-xl shadow-[inset_2px_2px_6px_rgba(0,0,0,0.4)] transition-all"
              autoFocus
            />
          </div>
        </div>

        <Button 
          type="submit"
          disabled={number.length < 8}
          className="w-full h-16 bg-primary-container hover:bg-primary text-surface-lowest rounded-full font-sans font-bold text-lg transition-all shadow-[0_10px_40px_-10px_rgba(135,129,255,0.5),inset_2px_2px_4px_rgba(255,255,255,0.4),inset_-2px_-2px_4px_rgba(0,0,0,0.2)] hover:shadow-[0_15px_50px_-10px_rgba(135,129,255,0.6),inset_2px_2px_4px_rgba(255,255,255,0.5),inset_-2px_-2px_4px_rgba(0,0,0,0.2)] hover:-translate-y-1 disabled:opacity-50 disabled:hover:shadow-none disabled:hover:translate-y-0"
        >
          Send Code
          <ArrowRight className="ml-3 h-6 w-6" />
        </Button>
      </form>
    </div>
  );
}
