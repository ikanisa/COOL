import React, { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { ArrowLeft, ArrowRight, Phone, Loader2, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { supabase } from "@/lib/supabase";

/* ── WhatsApp SVG icon ─────────────────────────────────────────────────── */
function WhatsAppIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 32 32" fill="none" className={className}>
      <circle cx="16" cy="16" r="14" fill="#25D366" />
      <path
        d="M23.3 8.7a10.2 10.2 0 0 0-16 12.2l-1.7 5 5.2-1.6a10.2 10.2 0 0 0 12.5-16.6Zm-5.1 14a8.4 8.4 0 0 1-4.3-1.2l-.3-.2-3.2 1 1-3-.2-.3A8.5 8.5 0 1 1 23 13a8.5 8.5 0 0 1-4.8 9.7Zm4.6-6.3c-.3-.1-1.5-.7-1.7-.8s-.4-.1-.6.2-.7.8-.8 1-.3.1-.6 0a7.5 7.5 0 0 1-3.8-3.4c-.3-.5.3-.5.8-1.6a.5.5 0 0 0 0-.4c0-.2-.5-1.3-.7-1.8s-.4-.4-.6-.4h-.5a.9.9 0 0 0-.7.3 3 3 0 0 0-.9 2.2 5.2 5.2 0 0 0 1.1 2.7 11.8 11.8 0 0 0 4.5 4c.6.3 1.1.5 1.5.6a3.6 3.6 0 0 0 1.7.1 2.7 2.7 0 0 0 1.8-1.3 2.2 2.2 0 0 0 .1-1.3c0-.1-.2-.2-.4-.3Z"
        fill="#fff"
      />
    </svg>
  );
}

/* ── Error extractor for supabase.functions.invoke ─────────────────────── */
function extractError(
  data: Record<string, unknown> | null,
  fnError: Error | null,
  fallback: string,
): string {
  if (data && typeof data === "object" && typeof data.message === "string") {
    return data.message;
  }
  if (fnError) {
    const msg = fnError.message;
    if (msg && !msg.includes("non-2xx")) return msg;
  }
  return fallback;
}

/* ── Contact Admin Modal ───────────────────────────────────────────────── */
function ContactAdminModal({ onClose }: { onClose: () => void }) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-6">
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/60 backdrop-blur-sm"
        onClick={onClose}
      />
      {/* Modal */}
      <div className="relative bg-surface-low/90 backdrop-blur-[40px] rounded-[2rem] p-8 max-w-sm w-full shadow-[0_20px_80px_-10px_rgba(13,10,39,0.9),inset_1px_1px_2px_rgba(255,255,255,0.05)] animate-in fade-in zoom-in-95 duration-200">
        <button
          onClick={onClose}
          className="absolute top-4 right-4 text-primary/50 hover:text-white transition-colors"
        >
          <X className="h-5 w-5" />
        </button>

        <div className="flex flex-col items-center text-center">
          <div className="h-16 w-16 bg-surface-lowest rounded-2xl flex items-center justify-center mb-6 shadow-[inset_2px_2px_6px_rgba(0,0,0,0.4)]">
            <WhatsAppIcon className="h-10 w-10" />
          </div>

          <h3 className="text-xl font-display font-bold text-white tracking-tight mb-3">
            Admin Access Required
          </h3>
          <p className="text-primary/70 text-sm leading-relaxed mb-6">
            This number is not registered as an admin user. Contact platform
            support to request access.
          </p>

          <a
            href="https://wa.me/250788767816?text=Hello%2C%20I%20would%20like%20to%20request%20admin%20access%20to%20the%20COOL%20platform."
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center gap-3 w-full justify-center h-14 bg-[#25D366] hover:bg-[#20bd5a] text-white rounded-full font-sans font-bold text-base transition-all hover:-translate-y-0.5 shadow-[0_8px_30px_-8px_rgba(37,211,102,0.5)]"
          >
            <WhatsAppIcon className="h-6 w-6" />
            Contact Support
          </a>

          <button
            onClick={onClose}
            className="mt-4 text-xs text-primary/50 hover:text-primary/80 font-label uppercase tracking-wider transition-colors"
          >
            Go back
          </button>
        </div>
      </div>
    </div>
  );
}

/* ── Main Component ────────────────────────────────────────────────────── */
export function WhatsAppNumber() {
  const [number, setNumber] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showContactModal, setShowContactModal] = useState(false);
  const navigate = useNavigate();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const trimmed = number.replace(/\s/g, "");
    if (trimmed.length < 8) return;

    setLoading(true);
    setError(null);

    const phone = trimmed.startsWith("+") ? trimmed : `+250${trimmed}`;

    try {
      // ── Step 1: Check if phone is an admin user ─────────────────
      const { data: isAdmin, error: rpcError } = await supabase.rpc(
        "check_admin_phone_access",
        { p_phone: phone },
      );

      if (rpcError) {
        console.error("Admin check RPC error:", rpcError);
        setError("Could not verify admin access. Please try again.");
        return;
      }

      if (!isAdmin) {
        setShowContactModal(true);
        return;
      }

      // ── Step 2: Send OTP (only if admin) ────────────────────────
      const { data, error: fnError } = await supabase.functions.invoke(
        "send-otp",
        { body: { phone, language: "en" } },
      );

      if (fnError || !data?.success) {
        setError(
          extractError(data, fnError, "Failed to send OTP. Please try again."),
        );
        return;
      }

      // OTP sent → navigate to verification screen
      navigate("/auth/whatsapp-otp", { state: { phone } });
    } catch (err) {
      setError(
        err instanceof Error
          ? err.message
          : "Network error. Please check your connection.",
      );
    } finally {
      setLoading(false);
    }
  };

  return (
    <>
      <div className="bg-surface-low/60 backdrop-blur-[40px] rounded-[3rem] p-10 shadow-[0_20px_80px_-10px_rgba(13,10,39,0.8),inset_1px_1px_2px_rgba(255,255,255,0.05),inset_-1px_-1px_2px_rgba(0,0,0,0.4)] relative">
        <div className="mb-10">
          <Link
            to="/auth/login"
            className="inline-flex items-center text-primary/60 hover:text-white transition-colors mb-8 text-sm font-label font-medium uppercase tracking-wider"
          >
            <ArrowLeft className="mr-2 h-4 w-4" />
            Back
          </Link>
          <h2 className="text-3xl font-display font-bold text-white tracking-tighter mb-3">
            Enter your number
          </h2>
          <p className="text-primary/70 text-base font-sans leading-relaxed">
            We'll send a secure code to your WhatsApp to verify your identity.
          </p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-8">
          <div className="space-y-3">
            <label className="text-sm font-label font-medium text-primary/80 uppercase tracking-wider">
              WhatsApp Number
            </label>
            <div className="relative flex items-center">
              <div className="absolute left-5 flex items-center gap-2 text-primary/60 font-mono text-lg">
                <Phone className="h-5 w-5" />
                <span>+250</span>
              </div>
              <Input
                type="tel"
                placeholder="788 123 456"
                value={number}
                onChange={(e) => {
                  setNumber(e.target.value);
                  setError(null);
                }}
                className="h-16 pl-28 bg-surface-lowest border-transparent text-white placeholder:text-primary/30 focus:border-electric-violet/40 focus:ring-1 focus:ring-electric-violet/40 rounded-[1.5rem] font-mono text-xl shadow-[inset_2px_2px_6px_rgba(0,0,0,0.4)] transition-all"
                autoFocus
                disabled={loading}
              />
            </div>
            {error && (
              <p className="text-sm text-rose-400 font-medium mt-2 animate-in fade-in slide-in-from-top-1">
                {error}
              </p>
            )}
          </div>

          <Button
            type="submit"
            disabled={number.replace(/\s/g, "").length < 8 || loading}
            className="w-full h-16 bg-primary-container hover:bg-primary text-surface-lowest rounded-full font-sans font-bold text-lg transition-all shadow-[0_10px_40px_-10px_rgba(135,129,255,0.5),inset_2px_2px_4px_rgba(255,255,255,0.4),inset_-2px_-2px_4px_rgba(0,0,0,0.2)] hover:shadow-[0_15px_50px_-10px_rgba(135,129,255,0.6),inset_2px_2px_4px_rgba(255,255,255,0.5),inset_-2px_-2px_4px_rgba(0,0,0,0.2)] hover:-translate-y-1 disabled:opacity-50 disabled:hover:shadow-none disabled:hover:translate-y-0"
          >
            {loading ? (
              <>
                <Loader2 className="mr-3 h-6 w-6 animate-spin" /> Verifying…
              </>
            ) : (
              <>
                Send Code <ArrowRight className="ml-3 h-6 w-6" />
              </>
            )}
          </Button>
        </form>
      </div>

      {/* Contact Admin Modal */}
      {showContactModal && (
        <ContactAdminModal onClose={() => setShowContactModal(false)} />
      )}
    </>
  );
}
