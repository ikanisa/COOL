import React, { useState, useRef, useEffect } from "react";
import { Link, useNavigate } from "react-router-dom";
import { ArrowLeft, CheckCircle2 } from "lucide-react";
import { Button } from "@/components/ui/button";

export function WhatsAppOTP() {
  const [otp, setOtp] = useState(["", "", "", "", "", ""]);
  const [isVerifying, setIsVerifying] = useState(false);
  const inputRefs = useRef<(HTMLInputElement | null)[]>([]);
  const navigate = useNavigate();

  useEffect(() => {
    if (inputRefs.current[0]) {
      inputRefs.current[0].focus();
    }
  }, []);

  const handleChange = (index: number, value: string) => {
    if (value.length > 1) {
      value = value.slice(-1);
    }
    
    const newOtp = [...otp];
    newOtp[index] = value;
    setOtp(newOtp);

    // Auto-advance
    if (value !== "" && index < 5) {
      inputRefs.current[index + 1]?.focus();
    }
  };

  const handleKeyDown = (index: number, e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === "Backspace" && otp[index] === "" && index > 0) {
      inputRefs.current[index - 1]?.focus();
    }
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const code = otp.join("");
    if (code.length === 6) {
      setIsVerifying(true);
      // Simulate verification
      setTimeout(() => {
        navigate("/");
      }, 1500);
    }
  };

  const isComplete = otp.every(digit => digit !== "");

  return (
    <div className="bg-surface-low/60 backdrop-blur-[40px] rounded-[3rem] p-10 shadow-[0_20px_80px_-10px_rgba(13,10,39,0.8),inset_1px_1px_2px_rgba(255,255,255,0.05),inset_-1px_-1px_2px_rgba(0,0,0,0.4)] relative">
      <div className="mb-10">
        <Link to="/auth/whatsapp-number" className="inline-flex items-center text-primary/60 hover:text-white transition-colors mb-8 text-sm font-label font-medium uppercase tracking-wider">
          <ArrowLeft className="mr-2 h-4 w-4" />
          Back
        </Link>
        <h2 className="text-3xl font-display font-bold text-white tracking-tighter mb-3">Verify it's you</h2>
        <p className="text-primary/70 text-base font-sans leading-relaxed">
          We sent a 6-digit code to your WhatsApp. Enter it below to access the platform.
        </p>
      </div>

      <form onSubmit={handleSubmit} className="space-y-10">
        <div className="flex justify-between gap-2 sm:gap-3">
          {otp.map((digit, index) => (
            <input
              key={index}
              ref={(el) => { inputRefs.current[index] = el; }}
              type="text"
              inputMode="numeric"
              pattern="[0-9]*"
              maxLength={1}
              value={digit}
              onChange={(e) => handleChange(index, e.target.value)}
              onKeyDown={(e) => handleKeyDown(index, e)}
              className="w-12 h-16 sm:w-14 sm:h-16 text-center bg-surface-lowest border-transparent text-white focus:border-electric-violet/40 focus:ring-1 focus:ring-electric-violet/40 rounded-[1.25rem] font-mono text-2xl shadow-[inset_2px_2px_6px_rgba(0,0,0,0.4)] transition-all"
            />
          ))}
        </div>

        <Button 
          type="submit"
          disabled={!isComplete || isVerifying}
          className="w-full h-16 bg-primary-container hover:bg-primary text-surface-lowest rounded-full font-sans font-bold text-lg transition-all shadow-[0_10px_40px_-10px_rgba(135,129,255,0.5),inset_2px_2px_4px_rgba(255,255,255,0.4),inset_-2px_-2px_4px_rgba(0,0,0,0.2)] hover:shadow-[0_15px_50px_-10px_rgba(135,129,255,0.6),inset_2px_2px_4px_rgba(255,255,255,0.5),inset_-2px_-2px_4px_rgba(0,0,0,0.2)] hover:-translate-y-1 disabled:opacity-50 disabled:hover:shadow-none disabled:hover:translate-y-0"
        >
          {isVerifying ? (
            <span className="flex items-center">
              <div className="h-5 w-5 border-2 border-surface-lowest/30 border-t-surface-lowest rounded-full animate-spin mr-3" />
              Verifying...
            </span>
          ) : (
            <span className="flex items-center">
              Verify & Login
              <CheckCircle2 className="ml-3 h-6 w-6" />
            </span>
          )}
        </Button>
      </form>

      <div className="mt-8 text-center">
        <button className="text-sm text-primary/80 hover:text-white font-label font-medium uppercase tracking-wider transition-colors">
          Didn't receive a code?
        </button>
      </div>
    </div>
  );
}
