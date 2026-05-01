import { useEffect, useRef, type ReactNode } from "react";
import { X } from "lucide-react";
import { cn } from "@/lib/utils";

interface DetailSheetProps {
  open: boolean;
  onClose: () => void;
  title: string;
  subtitle?: string;
  children: ReactNode;
  className?: string;
}

export function DetailSheet({ open, onClose, title, subtitle, children, className }: DetailSheetProps) {
  const panelRef = useRef<HTMLDivElement>(null);

  // Close on Escape
  useEffect(() => {
    if (!open) return;
    const handler = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    document.addEventListener("keydown", handler);
    return () => document.removeEventListener("keydown", handler);
  }, [open, onClose]);

  // Trap focus inside panel
  useEffect(() => {
    if (open && panelRef.current) {
      panelRef.current.focus();
    }
  }, [open]);

  if (!open) return null;

  return (
    <>
      {/* Backdrop */}
      <div
        className="fixed inset-0 z-50 bg-black/30 backdrop-blur-[2px] transition-opacity"
        onClick={onClose}
        aria-hidden="true"
      />

      {/* Sheet */}
      <div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-label={title}
        tabIndex={-1}
        className={cn(
          "fixed inset-y-0 right-0 z-50 w-full sm:w-[480px] bg-white shadow-2xl",
          "flex flex-col outline-none",
          "animate-in slide-in-from-right duration-200",
          className
        )}
      >
        {/* Header */}
        <div className="flex items-start justify-between px-6 py-5 border-b border-zinc-100">
          <div className="min-w-0">
            <h2 className="text-lg font-bold text-zinc-900 truncate">{title}</h2>
            {subtitle && (
              <p className="text-sm text-zinc-500 mt-0.5 truncate">{subtitle}</p>
            )}
          </div>
          <button
            onClick={onClose}
            className="ml-4 shrink-0 p-2 rounded-lg hover:bg-zinc-100 text-zinc-400 hover:text-zinc-600 transition-colors"
            aria-label="Close details"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Body */}
        <div className="flex-1 overflow-y-auto px-6 py-5">
          {children}
        </div>
      </div>
    </>
  );
}

/* ── Reusable detail row ────────────────────────────────────── */

interface DetailRowProps {
  label: string;
  value: ReactNode;
  mono?: boolean;
}

export function DetailRow({ label, value, mono }: DetailRowProps) {
  return (
    <div className="flex flex-col gap-1 py-3 border-b border-zinc-50 last:border-0">
      <dt className="text-xs font-medium text-zinc-400 uppercase tracking-wider">{label}</dt>
      <dd className={cn("text-sm text-zinc-900", mono && "font-mono text-xs")}>{value || "—"}</dd>
    </div>
  );
}

export function DetailSection({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className="mb-6">
      <h3 className="text-xs font-semibold text-zinc-500 uppercase tracking-wider mb-3">{title}</h3>
      <dl className="bg-zinc-50/50 rounded-xl px-4">
        {children}
      </dl>
    </div>
  );
}
