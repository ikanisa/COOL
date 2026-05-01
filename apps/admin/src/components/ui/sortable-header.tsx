import { useState } from "react";
import { ArrowUpDown, ArrowUp, ArrowDown } from "lucide-react";
import { TableHead } from "@/components/ui/table";

export type SortDirection = "asc" | "desc" | null;

interface SortableHeaderProps {
  label: string;
  sortKey: string;
  currentSort: string | null;
  currentDirection: SortDirection;
  onSort: (key: string) => void;
  className?: string;
}

export function SortableHeader({
  label,
  sortKey,
  currentSort,
  currentDirection,
  onSort,
  className = "",
}: SortableHeaderProps) {
  const isActive = currentSort === sortKey;

  return (
    <TableHead
      className={`cursor-pointer select-none hover:bg-zinc-50 transition-colors ${className}`}
      onClick={() => onSort(sortKey)}
    >
      <div className="flex items-center gap-1.5">
        <span>{label}</span>
        {isActive ? (
          currentDirection === "asc" ? (
            <ArrowUp className="h-3.5 w-3.5 text-indigo-600" />
          ) : (
            <ArrowDown className="h-3.5 w-3.5 text-indigo-600" />
          )
        ) : (
          <ArrowUpDown className="h-3.5 w-3.5 text-zinc-300" />
        )}
      </div>
    </TableHead>
  );
}

/** Hook for managing sort state */
export function useSort(defaultKey?: string, defaultDir: SortDirection = "desc") {
  const [sortKey, setSortKey] = useState<string | null>(defaultKey ?? null);
  const [sortDirection, setSortDirection] = useState<SortDirection>(defaultDir);

  const handleSort = (key: string) => {
    if (sortKey === key) {
      setSortDirection((d) => (d === "asc" ? "desc" : d === "desc" ? null : "asc"));
      if (sortDirection === null) setSortKey(null);
    } else {
      setSortKey(key);
      setSortDirection("desc");
    }
  };

  function sortData<T extends Record<string, unknown>>(data: T[]): T[] {
    if (!sortKey || !sortDirection) return data;
    return [...data].sort((a, b) => {
      const aVal = a[sortKey];
      const bVal = b[sortKey];
      if (aVal === bVal) return 0;
      if (aVal === null || aVal === undefined) return 1;
      if (bVal === null || bVal === undefined) return -1;
      const cmp = typeof aVal === "number" && typeof bVal === "number"
        ? aVal - bVal
        : String(aVal).localeCompare(String(bVal));
      return sortDirection === "asc" ? cmp : -cmp;
    });
  }

  return { sortKey, sortDirection, handleSort, sortData };
}

