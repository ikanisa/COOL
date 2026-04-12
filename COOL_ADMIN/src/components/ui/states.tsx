import { Loader2, AlertTriangle, SearchX, RotateCcw } from "lucide-react";
import { Button } from "@/components/ui/button";
import type { ReactNode } from "react";

/* ── Page-level skeleton loader ─────────────────────────────────── */

export function PageLoading({ message = "Loading…" }: { message?: string }) {
  return (
    <div className="flex flex-col items-center justify-center py-24 gap-4">
      <Loader2 className="h-8 w-8 animate-spin text-indigo-500" />
      <p className="text-sm text-zinc-500 font-medium">{message}</p>
    </div>
  );
}

/* ── Table skeleton rows ────────────────────────────────────────── */

export function TableSkeleton({ rows = 5, cols = 6 }: { rows?: number; cols?: number }) {
  return (
    <div className="w-full animate-pulse">
      {Array.from({ length: rows }).map((_, r) => (
        <div key={r} className="flex items-center gap-4 px-4 py-3 border-b border-zinc-100">
          {Array.from({ length: cols }).map((_, c) => (
            <div
              key={c}
              className="h-4 bg-zinc-200 rounded"
              style={{ width: `${60 + Math.random() * 80}px` }}
            />
          ))}
        </div>
      ))}
    </div>
  );
}

/* ── Error state with retry ────────────────────────────────────── */

export function PageError({
  message = "Failed to load data.",
  onRetry,
}: {
  message?: string;
  onRetry?: () => void;
}) {
  return (
    <div className="flex flex-col items-center justify-center py-24 gap-4">
      <div className="h-14 w-14 rounded-full bg-rose-100 flex items-center justify-center">
        <AlertTriangle className="h-7 w-7 text-rose-500" />
      </div>
      <p className="text-sm text-zinc-700 font-medium">{message}</p>
      {onRetry && (
        <Button variant="outline" onClick={onRetry} className="gap-2">
          <RotateCcw className="h-4 w-4" />
          Retry
        </Button>
      )}
    </div>
  );
}

/* ── Empty state ────────────────────────────────────────────────── */

export function EmptyState({
  icon,
  title = "No data found",
  description = "There are no items to display.",
  action,
}: {
  icon?: ReactNode;
  title?: string;
  description?: string;
  action?: ReactNode;
}) {
  return (
    <div className="flex flex-col items-center justify-center py-24 gap-4">
      <div className="h-14 w-14 rounded-full bg-zinc-100 flex items-center justify-center">
        {icon || <SearchX className="h-7 w-7 text-zinc-400" />}
      </div>
      <div className="text-center">
        <p className="text-sm font-medium text-zinc-900">{title}</p>
        <p className="text-sm text-zinc-500 mt-1">{description}</p>
      </div>
      {action}
    </div>
  );
}
